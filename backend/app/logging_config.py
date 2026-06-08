"""
Central logging setup for the SPAI backend.

One place to configure how logs look and what level they report at.
Import get_logger() anywhere that needs to log, instead of using print().
"""
import logging
import sys


def setup_logging(level: int = logging.INFO) -> None:
    """Configure the root logger once, at app startup.

    Format includes timestamp, level, and the logger's name so it's clear
    which part of the app a message came from.
    """
    logging.basicConfig(
        level=level,
        format="%(asctime)s | %(levelname)-7s | %(name)s | %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stdout,
        force=True,
    )


def get_logger(name: str) -> logging.Logger:
    """Get a named logger for a module.

    Usage at the top of a file:
        from app.logging_config import get_logger
        logger = get_logger(__name__)
    """
    return logging.getLogger(name)