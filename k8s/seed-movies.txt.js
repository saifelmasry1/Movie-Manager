db.movies.deleteMany({}); // اختياري: يمسح الداتا القديمة

db.movies.insertMany([
  {
    title: "The Shawshank Redemption",
    year: 1994,
    genre: "Drama",
    rating: 9.3,
    posterUrl: "/images/shawshank.jpg",
    description: "Two imprisoned men bond over a number of years..."
  },
  {
    title: "The Godfather",
    year: 1972,
    genre: "Crime",
    rating: 9.2,
    posterUrl: "/images/godfather.jpg",
    description: "The aging patriarch of an organized crime dynasty..."
  },
  {
    title: "The Dark Knight",
    year: 2008,
    genre: "Action",
    rating: 9.0,
    posterUrl: "/images/dark_knight.jpg",
    description: "Batman faces the Joker, a criminal mastermind..."
  },
  {
    title: "Pulp Fiction",
    year: 1994,
    genre: "Crime",
    rating: 8.9,
    posterUrl: "/images/pulp_fiction.jpg",
    description: "The lives of two mob hitmen, a boxer and others intersect..."
  },
  {
    title: "Fight Club",
    year: 1999,
    genre: "Drama",
    rating: 8.8,
    posterUrl: "/images/fight_club.jpg",
    description: "An office worker and a soap maker form an underground club..."
  },
  {
    title: "Forrest Gump",
    year: 1994,
    genre: "Drama",
    rating: 8.8,
    posterUrl: "/images/forrest_gump.jpg",
    description: "The story of Forrest, a simple man with a big heart..."
  },
  {
    title: "Inception",
    year: 2010,
    genre: "Sci-Fi",
    rating: 8.8,
    posterUrl: "/images/inception.jpg",
    description: "A thief who steals corporate secrets through dream-sharing..."
  },
  {
    title: "The Matrix",
    year: 1999,
    genre: "Sci-Fi",
    rating: 8.7,
    posterUrl: "/images/matrix.jpg",
    description: "A computer hacker learns the true nature of reality..."
  },
  {
    title: "Interstellar",
    year: 2014,
    genre: "Sci-Fi",
    rating: 8.6,
    posterUrl: "/images/interstellar.jpg",
    description: "A team of explorers travel through a wormhole in space..."
  },
  {
    title: "The Lord of the Rings: The Return of the King",
    year: 2003,
    genre: "Fantasy",
    rating: 8.9,
    posterUrl: "/images/lotr_return.jpg",
    description: "Gandalf and Aragorn lead the World of Men against Sauron..."
  },
  {
    title: "The Lion King",
    year: 1994,
    genre: "Animation",
    rating: 8.5,
    posterUrl: "/images/lion_king.jpg",
    description: "Lion prince Simba flees his kingdom after tragedy..."
  },
  {
    title: "Parasite",
    year: 2019,
    genre: "Thriller",
    rating: 8.5,
    posterUrl: "/images/parasite.jpg",
    description: "Greed and class discrimination threaten the symbiotic relationship..."
  }
]);
