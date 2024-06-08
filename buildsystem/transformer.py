from buildsystem.render_pass import *
from pathlib import Path
from shutil import copyfile, copytree


def transform(dest_path: Path, world_folders: list[WorldFolder]):
    root_dir = Path(".")
    root_files = root_dir.iterdir()
    excluded_dirs = ["buildsystem", "shaders", ".git", ".vscode"]
    for file in root_files:
        if file.is_file():
            if file.suffix != ".py":
                copyfile(file, dest_path / file.name)
        if file.is_dir():
            if not file.name in excluded_dirs:
                copytree(file, dest_path / file.name, dirs_exist_ok=True)

    src_path = Path("./shaders")
    dest_path = dest_path / "shaders"
    if not dest_path.exists():
        dest_path.mkdir(parents=True, exist_ok=True)

    files = src_path.iterdir()

    for file in files:
        if file.is_file():
            if file.name == "shaders.properties":
                transform_shaders_properties(file, dest_path, world_folders)
            else:
                copyfile(file, dest_path / file.name)
        if file.is_dir():
            if not file.name.startswith("world"):
                copytree(file, dest_path / file.name, dirs_exist_ok=True)
            else:
                for world_folder in world_folders:
                    if world_folder.world_dir == file.name:
                        copy_folder(dest_path, world_folder)


def transform_shaders_properties(
    src_path: Path, dest_path: Path, world_folders: list[WorldFolder]
):
    f = open(src_path, "r")
    lines = f.readlines()
    f.close()
    f = open(dest_path / "shaders.properties", "w")

    processed_lines = []

    for line in lines:
        processed_line = line
        for world_folder in world_folders:
            for pass_ in world_folder.deferred_passes:
                processed_line = processed_line.replace(
                    world_folder.world_dir + "/" + pass_.name,
                    world_folder.world_dir + "/" + pass_.allocated_name,
                )
            for pass_ in world_folder.composite_passes:
                processed_line = processed_line.replace(
                    world_folder.world_dir + "/" + pass_.name,
                    world_folder.world_dir + "/" + pass_.allocated_name,
                )
        processed_lines.append(processed_line)

    f.writelines(processed_lines)
    f.close()


def copy_folder(dest_path: Path, world_folder: WorldFolder):
    dest_path = dest_path / world_folder.world_dir
    if not dest_path.exists():
        dest_path.mkdir(parents=True, exist_ok=True)

    for file in world_folder.files:
        copy_to_dest(file, dest_path, world_folder)


def copy_to_dest(src_file: Path, dest_path: Path, world_folder: WorldFolder):
    copyfile(src_file, dest_path / world_folder.files[src_file])
