/*
=============================================================================

    Description: This is a character renderer
    Reference: https://github.com/moyongxin/mc-shaders-helpers

    Copyright © 2024 Mo Yongxin "qwertyuiop", Factorization, HaringPro 

=============================================================================

    How to use?
    1. Copy this file to your shaderpacks
    2. Include this file in your fragment shader
    3. Put your sentence in the follwing array
    4. Call the function renderText()

    Encoding
    uvec3(x:lower part,y:upper part,z:vertical offset)

    It use a 8*8(4*8*2) dot matrix

    eg:A

    original
    0 0 0 1 1 0 0 0
    0 0 1 0 0 1 0 0
    0 0 1 0 0 1 0 0
    0 1 0 0 0 0 1 0
    0 1 1 1 1 1 1 0
    0 1 0 0 0 0 1 0
    0 1 0 0 0 0 1 0
    0 1 0 0 0 0 1 0

    upper part
    <-<-<-<-<-<-<-
    0 0 0 1 1 0 0 0 (1)
    0 0 1 0 0 1 0 0 (2)
    0 0 1 0 0 1 0 0 (3)
    0 1 0 0 0 0 1 0 (4)
    lower part
    <-<-<-<-<-<-<-
    0 1 1 1 1 1 1 0 (1)
    0 1 0 0 0 0 1 0 (2)
    0 1 0 0 0 0 1 0 (3)
    0 1 0 0 0 0 1 0 (4)

    Read it form right to left, form from top to bottom
    lower part (1)01111110 (2)01000010 (3)01000010 (4)01000010
    upper part (1)00011000 (2)00100100 (3)00100100 (4)01000010

    Combine 0 and 1 together and convert to an unsigned 16-bit integer in hexadecimal format.

    lower part (1)01111110 (2)01000010 (3)01000010 (4)01000010 -> 0x7e424242u
    upper part (1)00011000 (2)00100100 (3)00100100 (4)01000010 -> 0x18242442u

    Place it into the XY components of a uvec3 (x is the lower half, y is the upper half).
    const uvec3 _A_ = uvec3(0x7e424242u,0x18242442u,0);

    When you need vertical offset,please change Z components of a uvec3

    If you don't like the style of characters,you can edit it by yourself.

    If you don't understand how it works,dont' edit the character code.

    It is strange that we can't use "char" as name of variable or constant on NVGPU.

=============================================================================
*/

//==============================// Character Encoding //======================================//

// Generated by qwertyuiop's generator
const uvec3 CHAR_A             = uvec3(0x11111100, 0x0E111F11, 1);
const uvec3 CHAR_B             = uvec3(0x11110F00, 0x0F110F11, 1);
const uvec3 CHAR_C             = uvec3(0x01110E00, 0x0E110101, 1);
const uvec3 CHAR_D             = uvec3(0x11110F00, 0x0F111111, 1);
const uvec3 CHAR_E             = uvec3(0x01011F00, 0x1F010701, 1);
const uvec3 CHAR_F             = uvec3(0x01010100, 0x1F010701, 1);
const uvec3 CHAR_G             = uvec3(0x11110E00, 0x1E011911, 1);
const uvec3 CHAR_H             = uvec3(0x11111100, 0x11111F11, 1);
const uvec3 CHAR_I             = uvec3(0x02020700, 0x07020202, 1);
const uvec3 CHAR_J             = uvec3(0x10110E00, 0x10101010, 1);
const uvec3 CHAR_K             = uvec3(0x11111100, 0x11090709, 1);
const uvec3 CHAR_L             = uvec3(0x01011F00, 0x01010101, 1);
const uvec3 CHAR_M             = uvec3(0x11111100, 0x111B1511, 1);
const uvec3 CHAR_N             = uvec3(0x11111100, 0x11131519, 1);
const uvec3 CHAR_O             = uvec3(0x11110E00, 0x0E111111, 1);
const uvec3 CHAR_P             = uvec3(0x01010100, 0x0F110F01, 1);
const uvec3 CHAR_Q             = uvec3(0x11091600, 0x0E111111, 1);
const uvec3 CHAR_R             = uvec3(0x11111100, 0x0F110F11, 1);
const uvec3 CHAR_S             = uvec3(0x10110E00, 0x1E010E10, 1);
const uvec3 CHAR_T             = uvec3(0x04040400, 0x1F040404, 1);
const uvec3 CHAR_U             = uvec3(0x11110E00, 0x11111111, 1);
const uvec3 CHAR_V             = uvec3(0x0A0A0400, 0x11111111, 1);
const uvec3 CHAR_W             = uvec3(0x151B1100, 0x11111111, 1);
const uvec3 CHAR_X             = uvec3(0x11111100, 0x110A040A, 1);
const uvec3 CHAR_Y             = uvec3(0x04040400, 0x110A0404, 1);
const uvec3 CHAR_Z             = uvec3(0x02011F00, 0x1F100804, 1);

const uvec3 CHAR_a             = uvec3(0x1E000000, 0x0E101E11, 3);
const uvec3 CHAR_b             = uvec3(0x11110F00, 0x01010D13, 1);
const uvec3 CHAR_c             = uvec3(0x0E000000, 0x0E110111, 3);
const uvec3 CHAR_d             = uvec3(0x11111E00, 0x10101619, 1);
const uvec3 CHAR_e             = uvec3(0x1E000000, 0x0E111F01, 3);
const uvec3 CHAR_f             = uvec3(0x02020200, 0x0C020F02, 1);
const uvec3 CHAR_g             = uvec3(0x100F0000, 0x1E11111E, 3);
const uvec3 CHAR_h             = uvec3(0x11111100, 0x01010D13, 1);
const uvec3 CHAR_i             = uvec3(0x01010100, 0x01000101, 1);
const uvec3 CHAR_j             = uvec3(0x1011110E, 0x10001010, 1);
const uvec3 CHAR_k             = uvec3(0x03050900, 0x01010905, 1);
const uvec3 CHAR_l             = uvec3(0x01010200, 0x01010101, 1);
const uvec3 CHAR_m             = uvec3(0x11000000, 0x0B151511, 3);
const uvec3 CHAR_n             = uvec3(0x11000000, 0x0F111111, 3);
const uvec3 CHAR_o             = uvec3(0x0E000000, 0x0E111111, 3);
const uvec3 CHAR_p             = uvec3(0x01010000, 0x0D13110F, 3);
const uvec3 CHAR_q             = uvec3(0x10100000, 0x1619111E, 3);
const uvec3 CHAR_r             = uvec3(0x01000000, 0x0D130101, 3);
const uvec3 CHAR_s             = uvec3(0x0F000000, 0x1E010E10, 3);
const uvec3 CHAR_t             = uvec3(0x02020400, 0x02070202, 1);
const uvec3 CHAR_u             = uvec3(0x1E000000, 0x11111111, 3);
const uvec3 CHAR_v             = uvec3(0x04000000, 0x1111110A, 3);
const uvec3 CHAR_w             = uvec3(0x1E000000, 0x11111515, 3);
const uvec3 CHAR_x             = uvec3(0x11000000, 0x110A040A, 3);
const uvec3 CHAR_y             = uvec3(0x100F0000, 0x1111111E, 3);
const uvec3 CHAR_z             = uvec3(0x1F000000, 0x1F080402, 3);

const uvec3 CHAR_0             = uvec3(0x13110E00, 0x0E111915, 1);
const uvec3 CHAR_1             = uvec3(0x04041F00, 0x04060404, 1);
const uvec3 CHAR_2             = uvec3(0x02011F00, 0x0E11100C, 1);
const uvec3 CHAR_3             = uvec3(0x10110E00, 0x0E11100C, 1);
const uvec3 CHAR_4             = uvec3(0x1F101000, 0x18141211, 1);
const uvec3 CHAR_5             = uvec3(0x10110E00, 0x1F010F10, 1);
const uvec3 CHAR_6             = uvec3(0x11110E00, 0x0C02010F, 1);
const uvec3 CHAR_7             = uvec3(0x04040400, 0x1F111008, 1);
const uvec3 CHAR_8             = uvec3(0x11110E00, 0x0E11110E, 1);
const uvec3 CHAR_9             = uvec3(0x10080600, 0x0E11111E, 1);

const uvec3 CHAR_UNDERSCORE    = uvec3(0x00000000, 0x1F000000, 8);
const uvec3 CHAR_EXCLAMATION   = uvec3(0x01000100, 0x01010101, 1);
const uvec3 CHAR_QUOTE         = uvec3(0x00000000, 0x05050000, 1);
const uvec3 CHAR_DOLLAR        = uvec3(0x100F0400, 0x041E010E, 1);
const uvec3 CHAR_PERCENT       = uvec3(0x02121100, 0x11090804, 1);
const uvec3 CHAR_AMPERSAND     = uvec3(0x0D091600, 0x040A0416, 1);
const uvec3 CHAR_APOSTROPHE    = uvec3(0x00000000, 0x01010000, 1);
const uvec3 CHAR_LEFT_PAREN    = uvec3(0x01020C00, 0x0C020101, 1);
const uvec3 CHAR_RIGHT_PAREN   = uvec3(0x08040300, 0x03040808, 1);
const uvec3 CHAR_ASTERISK      = uvec3(0x00000000, 0x09060900, 3);
const uvec3 CHAR_PLUS          = uvec3(0x04000000, 0x04041F04, 3);
const uvec3 CHAR_MINUS         = uvec3(0x00000000, 0x1F000000, 5);
const uvec3 CHAR_COLON         = uvec3(0x01010000, 0x01010000, 2);
const uvec3 CHAR_SEMICOLON     = uvec3(0x01010100, 0x01010000, 2);
const uvec3 CHAR_LESS_THAN     = uvec3(0x02040800, 0x08040201, 1);
const uvec3 CHAR_EQUAL         = uvec3(0x00000000, 0x1F00001F, 3);
const uvec3 CHAR_GREATER_THAN  = uvec3(0x04020100, 0x01020408, 1);
const uvec3 CHAR_QUESTION      = uvec3(0x04000400, 0x0E111008, 1);
const uvec3 CHAR_AT            = uvec3(0x3D013E00, 0x1E212D2D, 1);
const uvec3 CHAR_LEFT_BRACKET  = uvec3(0x01010700, 0x07010101, 1);
const uvec3 CHAR_RIGHT_BRACKET = uvec3(0x04040700, 0x07040404, 1);
const uvec3 CHAR_CARET         = uvec3(0x00000000, 0x040A1100, 1);
const uvec3 CHAR_BACKTICK      = uvec3(0x00000000, 0x02010000, 1);
const uvec3 CHAR_LEFT_BRACE    = uvec3(0x02020C00, 0x0C020201, 1);
const uvec3 CHAR_PIPE          = uvec3(0x01010100, 0x01010100, 1);
const uvec3 CHAR_RIGHT_BRACE   = uvec3(0x04040300, 0x03040408, 1);
const uvec3 CHAR_TILDE         = uvec3(0x00000000, 0x26190000, 1);
const uvec3 CHAR_COMMA         = uvec3(0x00000000, 0x01010100, 6);
const uvec3 CHAR_DOT           = uvec3(0x00000000, 0x01010000, 6);
const uvec3 CHAR_SLASH         = uvec3(0x02020100, 0x10080804, 1);
const uvec3 CHAR_BACKSLASH     = uvec3(0x08081000, 0x01020204, 1);
const uvec3 CHAR_HASH          = uvec3(0x1F0A0A00, 0x0A0A1F0A, 1);
const uvec3 CHAR_SPACE         = uvec3(0x00000000, 0x00000000, 8);


// Put your sentence in this array. Use comma to separate characters.
const uvec3 text[] = uvec3[](CHAR_A,CHAR_B,CHAR_C,CHAR_D,CHAR_E,CHAR_F,CHAR_G,CHAR_H,CHAR_I,CHAR_J,CHAR_K,CHAR_L,CHAR_M,CHAR_N,CHAR_O,CHAR_P,CHAR_Q,CHAR_R,CHAR_S,CHAR_T,CHAR_U,CHAR_V,CHAR_W,CHAR_X,CHAR_Y,CHAR_Z,CHAR_a,CHAR_b,CHAR_c,CHAR_d,CHAR_e,CHAR_f,CHAR_g,CHAR_h,CHAR_i,CHAR_j,CHAR_k,CHAR_l,CHAR_m,CHAR_n,CHAR_o,CHAR_p,CHAR_q,CHAR_r,CHAR_s,CHAR_t,CHAR_u,CHAR_v,CHAR_w,CHAR_x,CHAR_y,CHAR_z,CHAR_0,CHAR_1,CHAR_2,CHAR_3,CHAR_4,CHAR_5,CHAR_6,CHAR_7,CHAR_8,CHAR_9);

// Original Text: https://github.com/HaringPro/Revelation
const uvec3 text_encodings[] = {CHAR_h,CHAR_t,CHAR_t,CHAR_p,CHAR_s,CHAR_COLON,CHAR_SLASH,CHAR_SLASH,CHAR_g,CHAR_i,CHAR_t,CHAR_h,CHAR_u,CHAR_b,CHAR_DOT,CHAR_c,CHAR_o,CHAR_m,CHAR_SLASH,CHAR_H,CHAR_a,CHAR_r,CHAR_i,CHAR_n,CHAR_g,CHAR_P,CHAR_r,CHAR_o,CHAR_SLASH,CHAR_R,CHAR_e,CHAR_v,CHAR_e,CHAR_l,CHAR_a,CHAR_t,CHAR_i,CHAR_o,CHAR_n};
const int   text_advances[]  = {0,6,10,14,20,26,28,34,40,46,48,52,58,64,70,72,78,84,90,96,102,108,114,116,122,128,134,140,146,152,158,164,170,176,179,185,189,191,197};

//==============================// Character Render //========================================//

bool isChar(uint text, uint index) {
	return index < 32u && bool(text >> index & 1u); // Use the right shift operation to decode our character code
}

bool isText(ivec2 texel, ivec2 pos, uvec3 text, int size) {
    pos.y -= int(text.z) * size; // Vertical offset

    ivec2 relPos = (texel - pos) / size;

    // Calculate the index for the lower part
    // 8 is the number of columns in the character grid
    uint index = uint(relPos.x + relPos.y * 8); 

    // Lower part
    bool result = isChar(text.x, index);

    // Upper part
    result = result || isChar(text.y, index - 32u);

    return result;
}

vec3 renderText(ivec2 pos, int size, vec3 color) {
	vec3 result = vec3(0.0);
    ivec2 screenTexel = ivec2(gl_FragCoord.st);

    if (max(screenTexel, ivec2(pos.x, pos.y - size * 6)) == screenTexel) {
        int lastText = text_advances[text_encodings.length() - 1];
        if (min(screenTexel, ivec2(pos.x + size * (lastText + 6), pos.y + size * 6 + 12)) == screenTexel) {
            int relPos = screenTexel.x - pos.x;
            relPos /= size;

            // Binary search for the character index
            int left = 0, right = text_advances.length();
            while (left < right) {
                int middle = (left + right) >> 1;
                if (relPos >= text_advances[middle]) left = middle + 1;
                else right = middle;
            }

            int index = left - 1;
            pos += ivec2(size * text_advances[index], 0);
            result = float(isText(screenTexel, pos, text_encodings[index], size)) * color;
        }
    }

	return result;
}
