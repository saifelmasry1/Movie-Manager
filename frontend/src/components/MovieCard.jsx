import React from 'react';
import { Link } from 'react-router-dom';

const MovieCard = ({ movie }) => {
    return (
        <Link to={`/movie/${movie._id}`} className="movie-card-link">
            <div className="movie-card">
                <img
                    src={movie.posterUrl}
                    alt={movie.title}
                    className="movie-poster"
                    onError={(e) => {
                        e.target.src = 'https://via.placeholder.com/300x450?text=No+Poster';
                    }}
                />
                <div className="movie-info">
                    <h3>{movie.title}</h3>
                    <div className="movie-meta">
                        <span className="movie-year">{movie.year}</span>
                        <span className="movie-rating">★ {movie.rating}</span>
                    </div>
                    <p className="movie-genre">{movie.genre}</p>
                    <p className="movie-description">{movie.description}</p>
                </div>
            </div>
        </Link>
    );
};

export default MovieCard;
