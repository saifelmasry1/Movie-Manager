const mongoose = require('mongoose');
const dotenv = require('dotenv');
const Movie = require('../models/Movie');
const connectDB = require('../config/db');

// Load env vars
dotenv.config();

// Hardcoded list of 9 movies with LOCAL image paths
const movies = [
    {
        title: "The Shawshank Redemption",
        year: 1994,
        genre: "Drama",
        rating: 9.3,
        description: "Two imprisoned men bond over a number of years, finding solace and eventual redemption through acts of common decency.",
        posterUrl: "/images/shawshank.jpg"
    },
    {
        title: "The Godfather",
        year: 1972,
        genre: "Crime, Drama",
        rating: 9.2,
        description: "The aging patriarch of an organized crime dynasty transfers control of his clandestine empire to his reluctant son.",
        posterUrl: "/images/godfather.jpg"
    },
    {
        title: "The Dark Knight",
        year: 2008,
        genre: "Action, Crime, Drama",
        rating: 9.0,
        description: "When the menace known as the Joker wreaks havoc and chaos on the people of Gotham, Batman must accept one of the greatest psychological and physical tests of his ability to fight injustice.",
        posterUrl: "/images/dark_knight.jpg"
    },
    {
        title: "Pulp Fiction",
        year: 1994,
        genre: "Crime, Drama",
        rating: 8.9,
        description: "The lives of two mob hitmen, a boxer, a gangster and his wife, and a pair of diner bandits intertwine in four tales of violence and redemption.",
        posterUrl: "/images/pulp_fiction.jpg"
    },
    {
        title: "Inception",
        year: 2010,
        genre: "Action, Adventure, Sci-Fi",
        rating: 8.8,
        description: "A thief who steals corporate secrets through the use of dream-sharing technology is given the inverse task of planting an idea into the mind of a C.E.O.",
        posterUrl: "/images/inception.jpg"
    },
    {
        title: "Forrest Gump",
        year: 1994,
        genre: "Drama, Romance",
        rating: 8.8,
        description: "The presidencies of Kennedy and Johnson, the events of Vietnam, Watergate and other historical events unfold from the perspective of an Alabama man with an IQ of 75, whose only desire is to be reunited with his childhood sweetheart.",
        posterUrl: "/images/forrest_gump.jpg"
    },
    {
        title: "The Matrix",
        year: 1999,
        genre: "Action, Sci-Fi",
        rating: 8.7,
        description: "A computer hacker learns from mysterious rebels about the true nature of his reality and his role in the war against its controllers.",
        posterUrl: "/images/matrix.jpg"
    },
    {
        title: "Interstellar",
        year: 2014,
        genre: "Adventure, Drama, Sci-Fi",
        rating: 8.6,
        description: "A team of explorers travel through a wormhole in space in an attempt to ensure humanity's survival.",
        posterUrl: "/images/interstellar.jpg"
    },
    {
        title: "Parasite",
        year: 2019,
        genre: "Drama, Thriller",
        rating: 8.5,
        description: "Greed and class discrimination threaten the newly formed symbiotic relationship between the wealthy Park family and the destitute Kim clan.",
        posterUrl: "/images/parasite.jpg"
    },
    {
        title: "The Lord of the Rings: The Return of the King",
        year: 2003,
        genre: "Adventure, Drama, Fantasy",
        rating: 9.0,
        description: "Gandalf and Aragorn lead the World of Men against Sauron's army to draw his gaze from Frodo and Sam as they approach Mount Doom with the One Ring.",
        posterUrl: "/images/lotr_return.jpg"
    },
    {
        title: "Fight Club",
        year: 1999,
        genre: "Drama",
        rating: 8.8,
        description: "An insomniac office worker and a devil-may-care soap maker form an underground fight club that evolves into much more.",
        posterUrl: "/images/fight_club.jpg"
    },
    {
        title: "The Lion King",
        year: 1994,
        genre: "Animation, Adventure, Drama",
        rating: 8.5,
        description: "Lion prince Simba and his father are targeted by his bitter uncle, who wants to ascend the throne himself.",
        posterUrl: "/images/lion_king.jpg"
    }
];

const seedData = async () => {
    try {
        await connectDB();

        // Always clear existing data to ensure updates (like new image URLs) are applied
        console.log('Clearing existing movies...');
        await Movie.deleteMany({});

        console.log('Seeding new movie data...');
        await Movie.insertMany(movies);

        console.log('Movies seeded successfully!');
        process.exit();
    } catch (error) {
        console.error(`Error seeding data: ${error}`);
        process.exit(1);
    }
};

seedData();
