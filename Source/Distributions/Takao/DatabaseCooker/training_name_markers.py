"""Parse 〖name〗 and legacy ⟦name⟧ omissions without joining fragments."""
import re


NAME_MARKER = re.compile(r"(〖[^〖〗⟦⟧\r\n]+〗|⟦[^〖〗⟦⟧\r\n]+⟧)")
MARKER_DELIMITER = re.compile(r"[〖〗⟦⟧]")


def name_marker_parts(line: str, location: str) -> list[str]:
    parts = NAME_MARKER.split(line)
    names = [span[1:-1] for span in parts[1::2]]
    if (any(MARKER_DELIMITER.search(fragment) for fragment in parts[::2])
            or any(not name.strip() for name in names)):
        raise ValueError(f"{location}: malformed personal-name marker (expected 〖姓名〗 or ⟦姓名⟧)")
    parts[1::2] = names
    return parts
