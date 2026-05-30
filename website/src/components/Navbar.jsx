import { useState, useEffect } from 'react';
import { Link, useLocation } from 'react-router-dom';
import './Navbar.css';

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const location = useLocation();

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  useEffect(() => {
    setMobileOpen(false);
    document.body.style.overflow = '';
  }, [location]);

  const toggleMobile = () => {
    setMobileOpen(!mobileOpen);
    document.body.style.overflow = !mobileOpen ? 'hidden' : '';
  };

  const isActive = (path) => location.pathname === path ? 'active' : '';

  return (
    <>
      <nav className={`navbar ${scrolled ? 'scrolled' : ''}`}>
        <div className="navbar-inner">
          <Link to="/" className="navbar-logo">
            <div className="logo-icon">G</div>
            <span className="logo-text">Gaman</span>
          </Link>

          <div className="navbar-links">
            <a href="/#how-it-works">How It Works</a>
            <Link to="/for-drivers" className={isActive('/for-drivers')}>For Drivers</Link>
            <Link to="/for-riders" className={isActive('/for-riders')}>For Riders</Link>
            <Link to="/pricing" className={isActive('/pricing')}>Pricing</Link>
          </div>

          <div className="navbar-right">
            <span className="lang-toggle">
              <span className="lang-active">EN</span> | తె
            </span>
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
          </div>

          <div
            className={`navbar-mobile-toggle ${mobileOpen ? 'open' : ''}`}
            onClick={toggleMobile}
            aria-label="Toggle menu"
          >
            <span />
            <span />
            <span />
          </div>
        </div>
      </nav>

      <div className={`navbar-mobile-menu ${mobileOpen ? 'open' : ''}`}>
        <Link to="/">Home</Link>
        <a href="/#how-it-works" onClick={() => { setMobileOpen(false); document.body.style.overflow = ''; }}>How It Works</a>
        <Link to="/for-drivers">For Drivers</Link>
        <Link to="/for-riders">For Riders</Link>
        <Link to="/pricing">Pricing</Link>
        <Link to="/about">About</Link>
        <Link to="/support">Support</Link>
        <div className="mobile-cta">
          <a
            href="https://play.google.com/store"
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-primary"
          >
            Download App
          </a>
        </div>
      </div>
    </>
  );
}
