import React, { useState, useEffect } from 'react';
import axios from 'axios';
import MovieList from '../components/MovieList';
import { API_BASE_URL } from '../config/apiConfig';

const MoviesPage = () => {
    const [movies, setMovies] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        const fetchMovies = async () => {
            try {
                const response = await axios.get(`${API_BASE_URL}/movies`);
                setMovies(response.data);
                setLoading(false);
            } catch (err) {
                console.error("Error fetching movies:", err);
                setError("Failed to load movies. Please try again later.");
                setLoading(false);
            }
        };

        fetchMovies();
    }, []);

    if (loading) return <div className="loading">Loading movies...</div>;
    if (error) return <div className="error">{error}</div>;

    return (
        <div className="movies-page">
            <header className="app-header">
                <h1>Movie Manager 🎬</h1>
                <p>Top 9 Must-Watch Movies</p>
            </header>
            <main>
                <MovieList movies={movies} />
            </main>
        </div>
    );
};

export default MoviesPage;
