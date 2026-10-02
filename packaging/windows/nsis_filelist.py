#!/usr/bin/env python3
"""Write the NSIS include files that install and uninstall exactly the files
of a staged Kader folder, so the uninstaller never removes anything it did
not put there (even if Kader was installed into a folder with other files).

    nsis_filelist.py <stage-dir> <install.nsh> <uninstall.nsh>
"""
import os
import sys


def main() -> None:
    stage, install, uninstall = sys.argv[1:4]
    dirs = []
    files = []
    for top, subdirs, names in os.walk(stage):
        subdirs.sort()
        rel = os.path.relpath(top, stage)
        rel = "" if rel == "." else rel.replace("/", "\\")
        if rel:
            dirs.append(rel)
        for name in sorted(names):
            files.append((rel, name))

    with open(install, "w", encoding="utf-8") as f:
        current = None
        for rel, name in files:
            if rel != current:
                f.write(f'SetOutPath "$INSTDIR{chr(92) + rel if rel else ""}"\n')
                current = rel
            src = f"${{SRCDIR}}\\{rel}\\{name}" if rel else f"${{SRCDIR}}\\{name}"
            f.write(f'File "{src}"\n')
        f.write('SetOutPath "$INSTDIR"\n')

    with open(uninstall, "w", encoding="utf-8") as f:
        for rel, name in files:
            path = f"$INSTDIR\\{rel}\\{name}" if rel else f"$INSTDIR\\{name}"
            f.write(f'Delete "{path}"\n')
        # deepest first; RMDir only removes empty folders
        for rel in sorted(dirs, key=lambda d: d.count("\\"), reverse=True):
            f.write(f'RMDir "$INSTDIR\\{rel}"\n')

    print(f"{len(files)} files in {len(dirs) + 1} folders", file=sys.stderr)


if __name__ == "__main__":
    main()
