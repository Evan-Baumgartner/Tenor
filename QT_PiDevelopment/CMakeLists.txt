cmake_minimum_required(VERSION 3.22)

project(HomeAnomalyDetector
    VERSION 1.0.0
    DESCRIPTION "Home Audio Anomaly Detector UI"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ─── Qt configuration ─────────────────────────────────────────────────────────
# If CMake cannot find Qt automatically, uncomment and set this path:
# set(CMAKE_PREFIX_PATH "$ENV{HOME}/Qt/6.11.0/gcc_arm64" ${CMAKE_PREFIX_PATH})

find_package(Qt6 6.11 REQUIRED COMPONENTS
    Core
    Gui
    Quick
    Mqtt
)

qt_standard_project_setup()

# ─── Executable ───────────────────────────────────────────────────────────────
# Named "anomaly-ui" — deliberately different from the QML module URI
# "AnomalyDetector" to prevent the linker collision we saw earlier.
qt_add_executable(anomaly-ui
    main.cpp
    MqttHelper.h
)

# ─── QML module ───────────────────────────────────────────────────────────────
# URI "AnomalyDetector" sets the resource path: qrc:/AnomalyDetector/Main.qml
# This must match the URL loaded in main.cpp.
qt_add_qml_module(anomaly-ui
    URI AnomalyDetector
    VERSION 1.0
    QML_FILES
        Main.qml
)

# ─── Link libraries ───────────────────────────────────────────────────────────
target_link_libraries(anomaly-ui PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Mqtt
)

# ─── Install (used by the systemd service) ────────────────────────────────────
install(TARGETS anomaly-ui
    RUNTIME DESTINATION /usr/local/bin
)
