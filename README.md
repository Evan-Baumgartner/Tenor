# Tenor

## Inspiration
We were inspired by H&R Block's sponsored track to create something that could benefit several members of our community in their day-to-day lives. From this, we developed **Tenor**.

Technology greatly improves quality of life, but it should also be used to its fullest potential for those who need it most—such as the deaf and hard-of-hearing (HoH) community. We decided to leverage multiple hardware platforms to create an accessible home alert system tailored to their needs.

---

## What It Does
Tenor is a highly scalable home alert system designed to help deaf/HoH individuals feel more aware and comfortable in their homes.

Our custom hardware detects **auditory anomalies** and reports them to a central base station. A touchscreen interface then alerts the user and directs their attention to the event.

Examples of detectable sounds include:
- Baby crying  
- Glass breaking  
- Other critical environmental sounds  

This system enables users to stay in tune with their surroundings in a **cost-effective and reliable way**.

---

## How We Built It
- **Base Station**
  - Powered by a **Raspberry Pi 5**
  - Runs a **Qt framework** for the touchscreen interface
  - Communicates via **WiFi using MQTT**

- **Sound Sensor Module**
  - Built on an **ESP32-S3**
  - Uses a microphone module to capture audio waveforms
  - Processes audio using **machine learning**

- **Machine Learning**
  - Implemented using **Edge Impulse**
  - Uses anomaly detection to identify unusual sounds
  - Generates optimized **C++ code** for embedded deployment

---

## Challenges We Ran Into
This project presented several challenges, primarily related to **hardware compatibility**.

- Integrating multiple platforms into a cohesive system was difficult  
- Limited hardware availability required improvisation  
- Emergency trip to Micro Center for missing components  
- First-time experience with machine learning added complexity  

---

## Accomplishments That We're Proud Of
- Successfully designing and implementing a **custom hardware solution**
- Creating a system that is both **functional and cost-effective**
- Delivering a polished prototype despite **tight time constraints**
- Overcoming significant hardware limitations during development  

---

## What We Learned
- Hardware projects at hackathons are especially challenging due to limited resources  
- Initial ideas often need to be adapted based on available components  
- Rapid prototyping requires flexibility and creative problem-solving  
- Gained hands-on experience with **embedded ML and system integration**  

---

## What's Next for Tenor
With more development time, we plan to:
- Implement **advanced sound classification** (specific sound identification instead of general anomalies)
- Expand system scalability with additional sensor modules  
- Improve UI/UX for clearer and more intuitive alerts  

---

## Built With
- C++
- Python
- Edge Impulse
- ESP32
- MQTT (Mosquitto)
- PlatformIO
- Qt
- Raspberry Pi

---
