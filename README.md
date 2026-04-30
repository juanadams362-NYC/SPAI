# spai-visionos
SPAI is a visionOS-based sterile processing assistant that uses computer vision and AR overlays to guide surgical prep workflows, detect PPE issues, identify tools, and flag possible contamination risks.
# SPAI VisionOS

SPAI is a visionOS-based sterile processing assistant designed to support surgical prep workflows using computer vision, AR-style overlays, and AI-powered detection.

## Project Goal

The goal of SPAI is to help sterile processing students, technicians, and instructors identify possible workflow issues such as missing PPE, tool mismatch, hand hygiene concerns, and contamination risks.

## Core Features

- Vision Pro-style workflow interface
- Sterile prep step guidance
- AI detection alerts
- PPE and glove detection
- Surgical tool detection
- Mock live-feed demo mode
- Future Core ML integration for on-device inference

## Tech Stack

- SwiftUI
- RealityKit
- visionOS
- Python
- YOLOv8
- Google Colab
- Core ML

## Current Status

This project is currently in early prototype development. The first version focuses on building the visionOS app interface and training an initial YOLOv8 model for PPE/glove detection.

## Project Structure

```text
app/       visionOS app code
ml/        model training notebooks, scripts, and model outputs
docs/      project planning, architecture, and weekly logs
design/    Figma links and screenshots
demo/      sample images and videos
