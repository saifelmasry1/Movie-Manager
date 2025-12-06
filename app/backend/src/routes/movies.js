const express = require('express');
const router = express.Router();
const Movie = require('../models/Movie');

// GET /api/movies - Get all movies
router.get('/', async (req, res) => {
    try {
        const movies = await Movie.find({});
        res.json(movies);
    } catch (error) {
        res.status(500).json({ message: 'Server Error' });
    }
});

// GET /api/movies/:id - Get single movie
router.get('/:id', async (req, res) => {
    try {
        const movie = await Movie.findById(req.params.id);
        if (movie) {
            res.json(movie);
        } else {
            res.status(404).json({ message: 'Movie not found' });
        }
    } catch (error) {
        res.status(500).json({ message: 'Server Error' });
    }
});

module.exports = router;
