class Colors:
    """ANSI color codes for terminal output."""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    ENDC = '\033[0m'

    @classmethod
    def bold(cls, text): return f"{cls.BOLD}{text}{cls.ENDC}"
    @classmethod
    def cyan(cls, text): return f"{cls.CYAN}{text}{cls.ENDC}"
    @classmethod
    def green(cls, text): return f"{cls.GREEN}{text}{cls.ENDC}"
    @classmethod
    def yellow(cls, text): return f"{cls.YELLOW}{text}{cls.ENDC}"
    @classmethod
    def red(cls, text): return f"{cls.RED}{text}{cls.ENDC}"
    @classmethod
    def header(cls, text): return f"{cls.HEADER}{cls.BOLD}== {text} =={cls.ENDC}"

def print_header(text):
    """Prints a formatted header line."""
    print(f"\n{Colors.header(text)}")

def print_step(step_name, current, total):
    """Prints a formatted step indicator."""
    print(f"{Colors.BOLD}[{current}/{total}]{Colors.ENDC} {step_name}...")

def print_success(message):
    """Prints a formatted success message."""
    print(f"\n{Colors.GREEN}{Colors.BOLD}[SUCCESS]{Colors.ENDC} {message}")

def print_error(message):
    """Prints a formatted error message."""
    print(f"\n{Colors.RED}{Colors.BOLD}[ERROR]{Colors.ENDC} {message}")
