# Pocket Pitch

A Flutter cornhole game built with Flame and Riverpod.

## Features

- **Physics-based gameplay**: Flick to throw bags with realistic arc and gravity
- **Gyroscope support**: Use device tilt for lateral drift control
- **Theme system**: Switch between moon and boat visual themes
- **Score tracking**: Live score display with round completion tracking
- **State management**: Powered by Riverpod for reactive UI updates

## Tech Stack

- **Flutter**: Cross-platform UI framework
- **Flame**: 2D game engine for Flutter
- **Riverpod**: State management
- **sensors_plus**: Device sensor access

## Getting Started

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Dart SDK

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```

### Running the App

```bash
flutter run
```

## Game Assets

The game expects image assets in the following structure:

```
assets/images/
  moon/
    background.png
    board.png
    bag.png
  boat/
    background.png
    board.png
    bag.png
```

Place your game assets in these directories before running.

## Gameplay

- **Flick upward** to throw a bag toward the board
- **Swipe left/right** to aim
- **Tilt your device** to add lateral drift during flight
- Score points by landing on the board (1 pt) or in the hole (3 pts)
- Each round consists of 4 bag throws

## Development

This project uses a Flame game engine with a custom physics simulation for bag throwing. The game state is managed through Riverpod providers, allowing for clean separation between game logic and UI.
