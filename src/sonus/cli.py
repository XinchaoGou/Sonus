"""Typer CLI for local usage (optional; HTTP API remains the primary contract)."""

from pathlib import Path
from typing import Annotated

import typer
import uvicorn

from sonus.config import Settings
from sonus.factory import build_engine, build_tts_service
from sonus.logging_config import configure_logging
from sonus.schemas import AudioFormat
from sonus.factory import build_tts_service

app = typer.Typer(help="Sonus — local model-agnostic TTS", no_args_is_help=True)


@app.command()
def serve(
    host: Annotated[str | None, typer.Option(help="Bind host (default: SONUS_HOST)")] = None,
    port: Annotated[int | None, typer.Option(help="Bind port (default: SONUS_PORT)")] = None,
    log_level: Annotated[
        str | None,
        typer.Option("--log-level", "-l", help="Log level (default: SONUS_LOG_LEVEL)"),
    ] = None,
) -> None:
    """Run the FastAPI HTTP server."""
    settings = Settings()
    level = log_level if log_level is not None else settings.log_level
    configure_logging(level)
    bind_host = host if host is not None else settings.host
    bind_port = int(port if port is not None else settings.port)
    uvicorn.run(
        "sonus.app:app",
        host=bind_host,
        port=bind_port,
        factory=False,
        log_level=level.lower(),
    )


@app.command("tts")
def tts_cli(
    text: Annotated[str, typer.Option("--text", "-t", help="Text to synthesize")],
    output: Annotated[Path, typer.Option("--output", "-o", help="Output file path")],
    voice: Annotated[str, typer.Option("--voice", "-v", help="Logical or native voice id")] = "zh_female",
    speed: Annotated[float, typer.Option("--speed", "-s", help="Speed multiplier (0.5–2.0)")] = 1.0,
    fmt: Annotated[
        AudioFormat,
        typer.Option("--format", "-f", help="Output format", case_sensitive=False),
    ] = AudioFormat.wav,
) -> None:
    """Synthesize speech to a file (loads the engine locally; no HTTP server)."""
    if not (0.5 <= speed <= 2.0):
        raise typer.BadParameter("speed must be between 0.5 and 2.0")

    settings = Settings()
    engine = build_engine(settings)
    service = build_tts_service(settings, engine)
    try:
        result = service.synthesize_bytes(text=text, voice=voice, speed=speed, out_format=fmt)
    except ValueError as e:
        typer.echo(str(e), err=True)
        raise typer.Exit(code=2) from e
    except FileNotFoundError as e:
        typer.echo(str(e), err=True)
        raise typer.Exit(code=1) from e
    except RuntimeError as e:
        typer.echo(str(e), err=True)
        raise typer.Exit(code=1) from e

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(result.data)
    typer.echo(f"Wrote {len(result.data)} bytes to {output} (cache={result.cache})")


def main() -> None:
    app()


if __name__ == "__main__":
    main()
