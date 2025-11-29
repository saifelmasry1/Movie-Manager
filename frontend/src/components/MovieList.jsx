import React from 'react';
import MovieCard from './MovieCard';

const MovieList = ({ movies }) => {
    if (!movies || movies.length === 0) {
        return <div className="no-movies">No movies found.</div>;
    }

    return (
        <div className="movie-list">
            {movies.map((movie) => (
                <MovieCard key={movie._id} movie={movie} />
            ))}
        </div>
    );
};

export default MovieList;
