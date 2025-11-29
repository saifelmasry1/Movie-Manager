import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import MoviesPage from './pages/MoviesPage'
import MovieDetailsPage from './pages/MovieDetailsPage'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')).render(
    <React.StrictMode>
        <BrowserRouter>
            <Routes>
                <Route path="/" element={<MoviesPage />} />
                <Route path="/movie/:id" element={<MovieDetailsPage />} />
            </Routes>
        </BrowserRouter>
    </React.StrictMode>,
)
