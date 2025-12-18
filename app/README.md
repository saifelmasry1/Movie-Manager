# Movie Manager - Application Details

This directory contains the source code for the Movie Manager application, a simple MERN-stack inspire app (MongoDB, Express, React, Node) designed for DevOps demonstration purposes.

## Component Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Movie Manager Application                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│    ┌─────────────────────────────────────────────────────────────────┐  │
│    │                        FRONTEND (React)                         │  │
│    │                                                                 │  │
│    │   ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐    │  │
│    │   │  MoviesPage │    │ DetailsPage │    │   Components    │    │  │
│    │   │  (Grid)     │    │ (Single)    │    │   (Header,Card) │    │  │
│    │   └──────┬──────┘    └──────┬──────┘    └─────────────────┘    │  │
│    │          │                  │                                   │  │
│    │          └────────┬─────────┘                                   │  │
│    │                   ▼                                             │  │
│    │          axios.get("/api/movies")                               │  │
│    └───────────────────┬─────────────────────────────────────────────┘  │
│                        │ HTTP Request                                   │
│                        ▼                                                │
│    ┌─────────────────────────────────────────────────────────────────┐  │
│    │                     BACKEND (Node.js + Express)                 │  │
│    │                                                                 │  │
│    │   ┌──────────────────────────────────────────────────────────┐  │  │
│    │   │  Routes:                                                 │  │  │
│    │   │    GET /api/movies      → List all movies (JSON)        │  │  │
│    │   │    GET /api/movies/:id  → Get single movie              │  │  │
│    │   │    GET /health          → Health check                  │  │  │
│    │   └──────────────────────────────────────────────────────────┘  │  │
│    │                        │                                        │  │
│    │                        │ mongoose.find()                        │  │
│    │                        ▼                                        │  │
│    └───────────────────────────────────────────────────────────────────┘  │
│                        │                                                │
│                        ▼                                                │
│    ┌─────────────────────────────────────────────────────────────────┐  │
│    │                      DATABASE (MongoDB)                         │  │
│    │                                                                 │  │
│    │   Collection: movies                                            │  │
│    │   ┌──────────────────────────────────────────────────────────┐  │  │
│    │   │  { title, year, genre, rating, posterUrl, description } │  │  │
│    │   └──────────────────────────────────────────────────────────┘  │  │
│    │                                                                 │  │
│    │   Pre-seeded with 12 movies (via seedMovies.js)                │  │
│    └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1. Frontend (`/frontend`)
- **Tech**: React.js, Vite.
- **Port**: 3000 (Container), 5173 (Dev).
- **Features**:
  - Displays list of movies.
  - Responsive Grid Layout.
  - Fetches data from Backend API.
- **Configuration**:
  - `VITE_API_BASE_URL`: Environment variable to point to the backend service.

### 2. Backend (`/backend`)
- **Tech**: Node.js, Express.
- **Port**: 5000.
- **Features**:
  - REST API (`GET /api/movies`, `GET /api/movies/:id`).
  - Read-Only access to data.
  - Health check endpoint (`/health`).
- **Database Connection**:
  - Uses `mongoose` to connect to MongoDB.
  - `MONGODB_URI` environment variable.

### 3. Database
- **Tech**: MongoDB.
- **Seeding**: The app includes a seeding script (`src/seed/seedMovies.js`) to populate the database with initial data.

---

## Local Development (Docker Compose)

The easiest way to run the full stack locally is using Docker Compose.

### Start Application
```bash
docker compose up --build
```

### Seed Data
Once running, open a new terminal:
```bash
docker compose exec backend npm run seed
```

### Access
- **UI**: http://localhost:3000
- **API**: http://localhost:5000
