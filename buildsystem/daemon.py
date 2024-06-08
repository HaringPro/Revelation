from buildsystem.render_pass import WorldFolder
from buildsystem.transformer import copy_to_dest, transform_shaders_properties

from pathlib import Path
from shutil import copyfile
from watchdog.events import FileSystemEvent, FileModifiedEvent, FileSystemEventHandler
from watchdog.observers import Observer


class Daemon(FileSystemEventHandler):
    def __init__(self, dest_path: Path, world_folders: list[WorldFolder]):
        self.src_path = Path("./shaders")
        self.dest_path = dest_path
        self.world_folders = world_folders
        self.observer = Observer()
        self.observer.schedule(self, str(self.src_path), recursive=True)
        self.observer.start()
        try:
            while self.observer.is_alive():
                self.observer.join(1)
        except KeyboardInterrupt:
            self.observer.stop()
            self.observer.join()

    def on_modified(self, event: FileSystemEvent) -> None:
        if type(event) == FileModifiedEvent:
            print(f"WATCHDOG {event.src_path} modified")

            path = Path(event.src_path)
            if event.src_path.__contains__("world"):
                for world_folder in self.world_folders:
                    if path.parts.__contains__(world_folder.world_dir):
                        try:
                            copy_to_dest(
                                path,
                                self.dest_path / world_folder.world_dir,
                                world_folder,
                            )
                        except Exception as e:
                            print(f"Failed to copy {event.src_path}: {e}")
            elif path.name == "shaders.properties":
                transform_shaders_properties(path, self.dest_path, self.world_folders)
            else:
                rel_path = path.relative_to(self.src_path)
                copyfile(path, self.dest_path / rel_path)
