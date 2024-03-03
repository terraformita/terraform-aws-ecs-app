import os
import sys
import logging
from pythonjsonlogger import jsonlogger


class Base:

    logger = None

    def __config_logging(self):
        logger = logging.getLogger()
        formatter = jsonlogger.JsonFormatter()

        if logger.hasHandlers():
            # Replace the LambdaLoggerHandler formatter
            logger.handlers[0].setFormatter(formatter)
        else:
            # Setup local logging
            log_handler = logging.StreamHandler()
            log_handler.setFormatter(formatter)
            logger.addHandler(log_handler)

        logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))
        sys.excepthook = self.handle_uncaught_exception

        return logger

    def handle_uncaught_exception(self, exc_type, exc_value, exc_traceback):
        """
        This function will be called for uncaught exceptions.
        It logs the exception and then the program terminates.
        """
        logger = logging.getLogger()
        logger.critical("Uncaught exception", exc_info=(
            exc_type, exc_value, exc_traceback))

    def __init__(self, *args, **kwargs):
        if Base.logger is None:
            Base.logger = self.__config_logging()
        super().__init__(*args, **kwargs)

    def get_logger(self):
        return self.logger
