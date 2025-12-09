import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import axios from 'axios';
import { API_BASE_URL } from '../config/apiConfig';

const MovieDetailsPage = () => {
    const { id } = useParams();
    const navigate = useNavigate();
    const [movie, setMovie] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        const fetchMovie = async () => {
            try {
                const response = await axios.get(`${API_BASE_URL}/movies/${id}`);
                setMovie(response.data);
                setLoading(false);
            } catch (err) {
                console.error("Error fetching movie details:", err);
                setError("Failed to load movie details.");
                setLoading(false);
            }
        };

        fetchMovie();
    }, [id]);

    if (loading) return <div className="loading">Loading movie details...</div>;
    if (error) return <div className="error">{error}</div>;
    if (!movie) return <div className="error">Movie not found</div>;

    return (
        <div className="movie-details-page">
            <button onClick={() => navigate('/')} className="back-button">
                ← Back to Movies
            </button>
            <div className="movie-details-container">
                <div className="movie-details-poster">
                    <img
                        src={movie.posterUrl}
                        alt={movie.title}
                        onError={(e) => {
                            e.target.src = 'https://via.placeholder.com/300x450?text=No+Poster';
                        }}
                    />
                </div>
                <div className="movie-details-info">
                    <h1>{movie.title}</h1>
                    <div className="movie-meta-large">
                        <span className="movie-year">{movie.year}</span>
                        <span className="movie-rating">★ {movie.rating}</span>
                        <span className="movie-genre">{movie.genre}</span>
                    </div>
                    <div className="movie-description-large">
                        <h3>Description</h3>
                        <p>{movie.description}</p>
                    </div>
                    <div className="back-button-container">
                        {/* Since this opens in a new tab, we might not strictly need a back button, 
                 but it's good UX if they navigated here normally. 
                 However, user asked for new tab specifically. */}
                    </div>
                </div>
            </div>
        </div>
    );
};

export default MovieDetailsPage;
