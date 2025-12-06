# Movie Manager

A simple, read-only Movie Manager application built for a DevOps graduation project.
This project demonstrates a full-stack application using React, Node.js, Express, and MongoDB, fully containerized with Docker.

## Features

- **Read-Only Interface**: View a curated list of 9 movies.
- **Movie Details**: Displays title, year, genre, rating, description, and poster.
- **Simple Architecture**: Clean separation of concerns (Frontend, Backend, Database).
- **Containerized**: Runs easily with Docker Compose.

## Folder Structure

```
/
├── backend/            # Node.js + Express API
│   ├── src/
│   │   ├── config/     # Database configuration
│   │   ├── models/     # Mongoose models
│   │   ├── routes/     # API routes
│   │   ├── seed/       # Database seeding script
│   │   └── index.js    # Server entry point
│   ├── Dockerfile
│   └── package.json
│
├── frontend/           # React + Vite UI
│   ├── src/
│   │   ├── components/ # Reusable components
│   │   ├── config/     # API configuration
│   │   ├── pages/      # Page components
│   │   └── main.jsx    # App entry point
│   ├── Dockerfile
│   └── package.json
│
└── docker-compose.yml  # Orchestration for all services
```

## Prerequisites

- Node.js (v18 or higher)
- MongoDB (for local development)
- Docker & Docker Compose

## Getting Started

### Option 1: Running with Docker (Recommended)

1. **Build and start the containers:**
   ```bash
   docker compose up --build
   ```

2. **Seed the database (Run this in a separate terminal while containers are running):**
   ```bash
   docker compose exec backend npm run seed
   ```
   *Note: This populates the database with the 9 initial movies.*

3. **Access the application:**
   - Frontend: [http://localhost:3000](http://localhost:3000)
   - Backend API: [http://localhost:5000/api/movies](http://localhost:5000/api/movies)
   - Health Check: [http://localhost:5000/health](http://localhost:5000/health)

4. **Stop the application:**
   ```bash
   docker compose down
   ```

### Option 2: Running Locally

**1. Backend Setup:**

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```
2. Install dependencies:
   ```bash
   npm install
   ```
3. Create a `.env` file (optional, defaults provided in code):
   ```
   MONGODB_URI=mongodb://localhost:27017/movie_manager
   PORT=5000
   ```
4. Start MongoDB locally.
5. Seed the database:
   ```bash
   npm run seed
   ```
6. Start the server:
   ```bash
   npm run dev
   ```

**2. Frontend Setup:**

1. Navigate to the frontend directory:
   ```bash
   cd frontend
   ```
2. Install dependencies:
   ```bash
   npm install
   ```
3. Start the development server:
   ```bash
   npm run dev
   ```
4. Open [http://localhost:5173](http://localhost:5173) (or the port shown in your terminal).

## API Endpoints

- `GET /health`: Check server status.
- `GET /api/movies`: Retrieve all movies.
- `GET /api/movies/:id`: Retrieve a specific movie by ID.
