import argparse
import freetype


def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate text encodings using FreeType."
    )
    parser.add_argument("font", type=str, help="Path to the font file")
    parser.add_argument(
        "--charset-file",
        "-c",
        type=str,
        default="charset.txt",
        help="Path to the charset file",
    )
    parser.add_argument(
        "--output-charset-file",
        "-o",
        type=str,
        default=None,
        help="Output glsl definitions file",
    )
    parser.add_argument("--text", "-t", type=str, help="Text to render")
    return parser.parse_args()


def load_font(font_path):
    font_face = freetype.Face(font_path)

    # Set the font size, 8px * 8px
    font_face.set_pixel_sizes(8, 8)

    return font_face


def render_char(font_face, char):
    font_face.load_char(char, freetype.FT_LOAD_RENDER)

    return (
        font_face.glyph.bitmap,
        font_face.glyph.metrics.horiBearingX // 64,
        8 - font_face.glyph.metrics.horiBearingY // 64,
    )


def encode_bitmap_to_uvec2(bitmap, horizontal_offset=0):
    rows = bitmap.rows
    width = bitmap.width
    buffer = bitmap.buffer

    if rows > 8 or (width + horizontal_offset) > 8:
        raise ValueError("Bitmap is too large")

    u64 = 0
    for i in range(rows):
        for j in range(width):
            offset = (7 - i) * 8
            if buffer[i * width + j] > 0:
                u64 |= 1 << (offset + j + horizontal_offset)

    uvec2 = (u64 & 0xFFFFFFFF, u64 >> 32)
    return f"0x{uvec2[0]:08X}, 0x{uvec2[1]:08X}"


def read_charset(file_path):
    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.read()

    lines = lines.split("\n")
    lines = [line.strip("\n\t ") for line in lines if line.strip("\n\t ") != ""]
    lines = [line for line in lines if not line.startswith("#")]

    identifiers = {}

    for line in lines:
        line = line.split(" ")
        char = line[0]

        if len(line) > 1:
            identifier = line[1]
        else:
            identifier = char

        identifier = f"CHAR_{identifier}"
        identifiers[char] = identifier

    return identifiers


def convert_charset_to_glsl_defs(identifiers, font_face, file_path):
    with open(file_path, "w", encoding="utf-8") as f:
        for char, identifier in identifiers.items():
            bitmap, x_offset, y_offset = render_char(font_face, char)

            uvec2_def = encode_bitmap_to_uvec2(bitmap, x_offset)

            f.write(f"const uvec3 {identifier} = uvec3({uvec2_def}, {y_offset});\n")


def render_text(identifiers, font_face, text):
    pen = 0
    defs = f"\n// Original Text: {text}\n"
    defs += "const uvec3 text_encodings[] = {"
    advances = "const int text_advances[] = {"
    for char in text:
        defs += f"{identifiers[char]},"
        advances += f"{pen},"
        # Load the glyph for the character to calculate the horizontal offset
        # Currently WIP
        font_face.load_char(char, freetype.FT_LOAD_RENDER)
        pen += font_face.glyph.advance.x // 64

    defs += "};\n"
    advances += "};\n"
    return defs + advances


args = parse_args()

if args.output_charset_file == None and args.text == None:
    raise ValueError("No output specified")

font_face = load_font(args.font)
identifiers = read_charset(args.charset_file)

# Hardcoded identifiers
identifiers["#"] = "CHAR_HASH"
identifiers[" "] = "CHAR_SPACE"

if args.output_charset_file != None:
    convert_charset_to_glsl_defs(identifiers, font_face, args.output_charset_file)

if args.text != None:
    print(render_text(identifiers, font_face, args.text))
