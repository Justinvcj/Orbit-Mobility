# Equinox - Open-Source Ride-Hailing Ecosystem

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![NodeJS](https://img.shields.io/badge/node.js-6DA55F?style=for-the-badge&logo=node.js&logoColor=white)
![Socket.io](https://img.shields.io/badge/Socket.io-black?style=for-the-badge&logo=socket.io&badgeColor=010101)
![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![OpenStreetMap](https://img.shields.io/badge/OpenStreetMap-%237FBA00.svg?style=for-the-badge&logo=OpenStreetMap&logoColor=white)

## Overview
Welcome to **Equinox**, the future of open-source ride-hailing. Featuring the sleek **"Midnight Premium" dark UI**, Equinox provides cutting-edge real-time geospatial tracking. With a strategic pivot to a completely free, open-source routing engine powered by **OpenStreetMap (OSM)** and **OSRM**, Equinox entirely bypasses expensive Google Maps billing while delivering top-tier performance and accuracy.

## System Architecture
Equinox is built on a robust, highly scalable 3-tier architecture:
- **Flutter Clients**: Cross-platform, high-performance mobile applications for both Riders and Drivers, built with Flutter.
- **Node.js/Socket.io Central Dispatch**: A blazing fast, event-driven backend signaling server that handles live dispatching, driver-rider matching, and real-time location telemetry.
- **Supabase PostgreSQL Vault**: A secure, scalable backend-as-a-service providing database management, authentication, and a robust ledger for all system data.

## Key Features
- **Dynamic Pricing Engine**: Intelligent fare calculation adapting to real-time supply and demand.
- **Live Marker Interpolation (Bearing/Rotation)**: Ultra-smooth geospatial tracking with accurate vehicle bearing and rotation.
- **Haptic Feedback**: Meaningful physical device responses for a highly engaging user experience.
- **Photon Autocomplete**: Blazing fast, privacy-respecting location search and address autocomplete.
- **Digital Wallet Ledger**: Secure, immutable transaction logging for riders and drivers using Supabase PostgreSQL.

## Local Setup Instructions

Follow these exact commands to boot the ecosystem locally:

### 1. Central Dispatch Server
Navigate to the server directory, install dependencies, and start the node service:
```bash
cd server_backend
npm install
node index.js
```

### 2. Flutter Mobile Clients
Open separate terminals for the rider and driver applications:

**Rider App:**
```bash
cd rider_app
flutter run --dart-define-from-file=../.env
```

**Driver App:**
```bash
cd driver_app
flutter run --dart-define-from-file=../.env
```
