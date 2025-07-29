
struct ExposureData {
    uint histogram[HISTOGRAM_BIN_COUNT];
    float value;
};

layout (std430, binding = 0) buffer GlobalData {
    ExposureData exposure;
} global;
