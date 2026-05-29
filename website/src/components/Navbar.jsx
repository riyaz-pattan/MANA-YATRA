import { useState, useEffect } from 'react';
import { Link, useLocation } from 'react-router-dom';
import './Navbar.css';

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const location = useLocation();

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 40);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  useEffect(() => {
    setMobileOpen(false);
  }, [location]);

  const isActive = (path) => location.pathname === path ? 'active' : '';

  return (
    <>
      <nav className={`navbar ${scrolled ? 'scrolled' : ''}`}>
        <div className="navbar-inner">
          <Link to="/" className="navbar-logo">
            <div className="logo-icon">G</div>
            <span>Gaman</span>
          </Link>

          <div className="navbar-links">
            <Link to="/" className={isActive('/')}>Home</Link>
            <a href="/#how-it-works">How It Works</a>
            <a href="/#faq">FAQ</a>
            <Link to="/support" className={isActive('/support')}>Support</Link>
          </div>

          <div className="navbar-cta">
            <a
              href="https://play.google.com/store"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-primary"
            >
              Download App
            </a>
          </div>

          <div
            className={`navbar-mobile-toggle ${mobileOpen ? 'open' : ''}`}
            onClick={() => setMobileOpen(!mobileOpen)}
            aria-label="Toggle menu"
          >
            <span />
            <span />
            <span />
          </div>
        </div>
      </nav>

      <div className={`navbar-mobile-menu ${mobileOpen ? 'open' : ''}`}>
        <Link to="/" className={isActive('/')}>Home</Link>
        <a href="/#how-it-works" onClick={() => setMobileOpen(false)}>How It Works</a>
        <a href="/#faq" onClick={() => setMobileOpen(false)}>FAQ</a>
        <Link to="/support" className={isActive('/support')}>Support</Link>
        <Link to="/data-deletion">Data Deletion</Link>
        <a
          href="https://play.google.com/store"
          target="_blank"
          rel="noopener noreferrer"
          className="btn btn-primary"
          style={{ marginTop: '1rem', textAlign: 'center' }}
        >
          Download App
        </a>
      </div>
    </>
  );
}
