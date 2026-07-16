import os
import logging
from datetime import datetime

class Logger:
    @staticmethod
    def get_logger(category):
        """
        Returns a configured logger for a specific category (infra, tunnel, secrets).
        Logs are stored in logs/{category}/{category}-YYYY-MM-DD.log
        """
        # Ensure category dir exists
        root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        log_dir = os.path.join(root_dir, "logs", category)
        if not os.path.exists(log_dir):
            os.makedirs(log_dir)

        # Date-based filename
        today = datetime.now().strftime("%Y-%m-%d")
        log_file = os.path.join(log_dir, f"{category}-{today}.log")

        logger = logging.getLogger(category)
        
        # Avoid adding multiple handlers if logger is already configured
        if not logger.handlers:
            logger.setLevel(logging.INFO)
            
            # File handler (Daily rotation managed by static name change each run)
            fh = logging.FileHandler(log_file, mode='a', encoding='utf-8')
            formatter = logging.Formatter('%(asctime)s | %(levelname)-8s | %(message)s')
            fh.setFormatter(formatter)
            logger.addHandler(fh)
            
            # Optionally add a console handler if needed, 
            # but usually the CLI handles the console directly.

        return logger

def log_infra(message, level="info"):
    logger = Logger.get_logger("infra")
    getattr(logger, level.lower())(message)

def log_tunnel(message, level="info"):
    logger = Logger.get_logger("tunnel")
    getattr(logger, level.lower())(message)

def log_secrets(message, level="info"):
    logger = Logger.get_logger("secrets")
    getattr(logger, level.lower())(message)

def log_terraform(message, level="info"):
    logger = Logger.get_logger("terraform")
    getattr(logger, level.lower())(message)
