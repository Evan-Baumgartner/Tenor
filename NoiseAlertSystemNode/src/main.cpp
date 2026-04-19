#define EIDSP_QUANTIZE_FILTERBANK   0

#include <Audio-Anomaly-Detector_inferencing.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/i2s.h"
#include <WiFi.h>
#include <PubSubClient.h>

// Forward declarations
static bool microphone_inference_start(uint32_t n_samples);
static bool microphone_inference_record(void);
static int microphone_audio_signal_get_data(size_t offset, size_t length, float *out_ptr);
static void microphone_inference_end(void);
static int i2s_init(uint32_t sampling_rate);
static int i2s_deinit(void);
static void capture_samples(void* arg);
static void audio_inference_callback(uint32_t n_bytes);

// Pin definitions
#define I2S_WS    4
#define I2S_SCK   6
#define I2S_SD    21
#define DC_OFFSET -127238144

// WiFi & MQTT config
const char* name        = "Bedroom";
const char* ssid        = "******";
const char* password    = "******";
const char* mqtt_server = "***.**.*.**";
const int   mqtt_port   = 1883;

// Anomaly threshold
#define ANOMALY_THRESHOLD 6

WiFiClient espClient;
PubSubClient client(espClient);

typedef struct {
    signed short *buffers[2];
    unsigned char buf_select;
    unsigned char buf_ready;
    unsigned int buf_count;
    unsigned int n_samples;
} inference_t;

static inference_t inference;
static const uint32_t sample_buffer_size = 2048;
static signed short sampleBuffer[sample_buffer_size];
static bool debug_nn = false;
static int print_results = -(EI_CLASSIFIER_SLICES_PER_MODEL_WINDOW);
static bool record_status = true;

// WiFi functions
void setup_wifi() {
    WiFi.begin(ssid, password);
    Serial.print("Connecting to WiFi");
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\nWiFi connected");
    Serial.println(WiFi.localIP());
}

void callback(char* topic, byte* payload, unsigned int length) {
    Serial.print("Message on topic: ");
    Serial.println(topic);
}

void reconnect() {
    while (!client.connected()) {
        Serial.print("Connecting to MQTT...");
        if (client.connect(name)) {
            Serial.println("MQTT connected");
            client.subscribe("pi/commands");
        } else {
            Serial.printf("MQTT failed, rc=%d, retrying in 5s\n", client.state());
            delay(5000);
        }
    }
}

void publish_anomaly(float score) {
    if (!client.connected()) reconnect();
    client.loop();

    char topic[50];
    char payload[100];
    snprintf(topic, sizeof(topic), "home/anomaly/%s", name);
    snprintf(payload, sizeof(payload), "{\"node_id\":\"%s\",\"anomaly_score\":%.2f}", name, score);
    client.publish(topic, payload);
    Serial.printf("Published anomaly: %s\n", payload);
}

void setup() {
    Serial.begin(115200);
    delay(2000);
    Serial.println("Edge Impulse Audio Anomaly Detector");

    setup_wifi();
    client.setServer(mqtt_server, mqtt_port);
    client.setCallback(callback);
    reconnect();

    ei_printf("Inferencing settings:\n");
    ei_printf("\tInterval: %.2f ms.\n", (float)EI_CLASSIFIER_INTERVAL_MS);
    ei_printf("\tFrame size: %d\n", EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE);
    ei_printf("\tSample length: %d ms.\n", EI_CLASSIFIER_RAW_SAMPLE_COUNT / 16);

    run_classifier_init();
    ei_sleep(2000);

    if (microphone_inference_start(EI_CLASSIFIER_SLICE_SIZE) == false) {
        ei_printf("ERR: Could not allocate audio buffer (size %d)\r\n", EI_CLASSIFIER_RAW_SAMPLE_COUNT);
        return;
    }

    ei_printf("Listening for anomalies...\n");
}

void loop() {
    // Keep MQTT alive
    if (!client.connected()) reconnect();
    client.loop();

    bool m = microphone_inference_record();
    if (!m) {
        ei_printf("ERR: Failed to record audio...\n");
        return;
    }

    signal_t signal;
    signal.total_length = EI_CLASSIFIER_SLICE_SIZE;
    signal.get_data = &microphone_audio_signal_get_data;
    ei_impulse_result_t result = {0};

    EI_IMPULSE_ERROR r = run_classifier_continuous(&signal, &result, debug_nn);
    if (r != EI_IMPULSE_OK) {
        ei_printf("ERR: Failed to run classifier (%d)\n", r);
        return;
    }

    if (++print_results >= (EI_CLASSIFIER_SLICES_PER_MODEL_WINDOW)) {
#if EI_CLASSIFIER_HAS_ANOMALY == 1
        float score = result.anomaly;
        ei_printf("Anomaly score: ");
        ei_printf_float(score);
        ei_printf("\n");

        if (score > ANOMALY_THRESHOLD) {
            ei_printf("!!! ANOMALY DETECTED !!!\n");
            publish_anomaly(score);
        }
#endif
        print_results = 0;
    }
}

static void audio_inference_callback(uint32_t n_bytes) {
    for (int i = 0; i < n_bytes >> 1; i++) {
        inference.buffers[inference.buf_select][inference.buf_count++] = sampleBuffer[i];

        if (inference.buf_count >= inference.n_samples) {
            inference.buf_select ^= 1;
            inference.buf_count = 0;
            inference.buf_ready = 1;
        }
    }
}

static void capture_samples(void* arg) {
    const int32_t i2s_bytes_to_read = (uint32_t)arg;
    size_t bytes_read = i2s_bytes_to_read;

    while (record_status) {
        int32_t raw32[i2s_bytes_to_read / 2];
        i2s_read((i2s_port_t)1, (void*)raw32, i2s_bytes_to_read * 2, &bytes_read, 100);

        if (bytes_read <= 0) {
            ei_printf("Error in I2S read : %d", bytes_read);
        } else {
            for (int x = 0; x < i2s_bytes_to_read / 2; x++) {
                int32_t s = raw32[x] - DC_OFFSET;
                s = s >> 8;
                s = s * 4;
                if (s > 32767)  s = 32767;
                if (s < -32767) s = -32767;
                sampleBuffer[x] = (int16_t)s;
            }

            if (record_status) {
                audio_inference_callback(i2s_bytes_to_read);
            } else {
                break;
            }
        }
    }
    vTaskDelete(NULL);
}

static bool microphone_inference_start(uint32_t n_samples) {
    inference.buffers[0] = (signed short *)malloc(n_samples * sizeof(signed short));
    if (inference.buffers[0] == NULL) return false;

    inference.buffers[1] = (signed short *)malloc(n_samples * sizeof(signed short));
    if (inference.buffers[1] == NULL) {
        ei_free(inference.buffers[0]);
        return false;
    }

    inference.buf_select = 0;
    inference.buf_count = 0;
    inference.n_samples = n_samples;
    inference.buf_ready = 0;

    if (i2s_init(EI_CLASSIFIER_FREQUENCY)) {
        ei_printf("Failed to start I2S!");
        return false;
    }

    ei_sleep(100);
    record_status = true;

    xTaskCreate(capture_samples, "CaptureSamples", 1024 * 32, (void*)sample_buffer_size, 10, NULL);

    return true;
}

static bool microphone_inference_record(void) {
    bool ret = true;

    if (inference.buf_ready == 1) {
        ei_printf("Error sample buffer overrun.\n");
        ret = false;
    }

    while (inference.buf_ready == 0) {
        delay(1);
    }

    inference.buf_ready = 0;
    return ret;
}

static int microphone_audio_signal_get_data(size_t offset, size_t length, float *out_ptr) {
    numpy::int16_to_float(&inference.buffers[inference.buf_select ^ 1][offset], out_ptr, length);
    return 0;
}

static void microphone_inference_end(void) {
    i2s_deinit();
    ei_free(inference.buffers[0]);
    ei_free(inference.buffers[1]);
}

static int i2s_init(uint32_t sampling_rate) {
    i2s_config_t i2s_config = {
        .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
        .sample_rate = sampling_rate,
        .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
        .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
        .communication_format = I2S_COMM_FORMAT_STAND_MSB,
        .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
        .dma_buf_count = 8,
        .dma_buf_len = 512,
        .use_apll = false,
        .tx_desc_auto_clear = false,
        .fixed_mclk = 0,
    };

    i2s_pin_config_t pin_config = {
        .bck_io_num   = I2S_SCK,
        .ws_io_num    = I2S_WS,
        .data_out_num = I2S_PIN_NO_CHANGE,
        .data_in_num  = I2S_SD,
    };

    esp_err_t ret = 0;

    ret = i2s_driver_install((i2s_port_t)1, &i2s_config, 0, NULL);
    if (ret != ESP_OK) ei_printf("Error in i2s_driver_install");

    ret = i2s_set_pin((i2s_port_t)1, &pin_config);
    if (ret != ESP_OK) ei_printf("Error in i2s_set_pin");

    ret = i2s_zero_dma_buffer((i2s_port_t)1);
    if (ret != ESP_OK) ei_printf("Error in initializing dma buffer");

    return int(ret);
}

static int i2s_deinit(void) {
    i2s_driver_uninstall((i2s_port_t)1);
    return 0;
}

#if !defined(EI_CLASSIFIER_SENSOR) || EI_CLASSIFIER_SENSOR != EI_CLASSIFIER_SENSOR_MICROPHONE
#error "Invalid model for current sensor."
#endif