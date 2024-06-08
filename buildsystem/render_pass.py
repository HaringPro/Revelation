from pathlib import Path


class RenderPass:
    def __init__(self, path: Path, name: str, allocated_name: str):
        self.path = path
        self.name = name
        self.allocated_name = allocated_name
        self.shaders = {}

    def add_shader(self, shader: Path, suffix: str):
        self.shaders[shader] = self.allocated_name + suffix
        return (shader, self.shaders[shader])


class WorldFolder:
    def __init__(
        self,
        world_dir: str,
        deferred_pass_names: list[str],
        composite_pass_names: list[str],
    ):
        self.path = Path("./shaders") / world_dir
        self.world_dir = world_dir
        self.files = {}
        self.other_files = {}

        def helper_f(x):
            if x == 0:
                return ""
            else:
                return str(x)

        self.deferred_passes = list(
            map(
                lambda idx_name: RenderPass(
                    path=Path,
                    name=idx_name[1],
                    allocated_name="deferred" + helper_f(idx_name[0]),
                ),
                enumerate(deferred_pass_names),
            )
        )
        self.composite_passes = list(
            map(
                lambda idx_name: RenderPass(
                    path=Path,
                    name=idx_name[1],
                    allocated_name="composite" + helper_f(idx_name[0]),
                ),
                enumerate(composite_pass_names),
            )
        )

        self.map_name_to_pass = {}
        for pass_ in self.deferred_passes:
            self.map_name_to_pass[pass_.name] = pass_
        for pass_ in self.composite_passes:
            self.map_name_to_pass[pass_.name] = pass_

        legal_suffixes = [".csh", ".gsh", ".vsh", ".fsh"]
        files = Path.iterdir(self.path)
        for file in files:
            match file.suffix:
                case suffix if suffix in legal_suffixes:
                    name = file.stem

                    if suffix == ".csh":
                        tmp = name.split("_")
                        pass_name = tmp[0]
                        if len(tmp) > 1:
                            suffix = "_" + tmp[1] + suffix
                    else:
                        pass_name = name

                    if pass_name in self.map_name_to_pass:
                        _, allocated_name = self.map_name_to_pass[pass_name].add_shader(
                            file, suffix
                        )
                        self.files[file] = allocated_name
                    else:
                        self.files[file] = file.name

                case _:
                    continue

        for pass_ in self.deferred_passes:
            print(f"{pass_.name} -> {pass_.allocated_name}")

        for pass_ in self.composite_passes:
            print(f"{pass_.name} -> {pass_.allocated_name}")
