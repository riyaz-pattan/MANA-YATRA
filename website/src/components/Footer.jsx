import { Link } from 'react-router-dom';
import './Footer.css';

export default function Footer() {
  return (
    <footer className="footer">
      <div className="container">
        <div className="footer-grid">
          <div className="footer-brand">
            <div className="footer-logo">
              <div className="footer-logo-icon">G</div>
              <span className="footer-logo-text">Gaman</span>
            </div>
            <p>
              The ride platform that works for everyone. Zero commission rides,
              fair prices, and 100% earnings for drivers.
            </p>
            <p style={{ marginTop: 8, fontFamily: 'var(--font-telugu)', fontSize: 13 }}>
              మన Hyderabad కి మన app.
            </p>
            <div className="footer-social">
              <a href="#" aria-label="Twitter">𝕏</a>
              <a href="#" aria-label="Instagram">📷</a>
              <a href="#" aria-label="LinkedIn">in</a>
            </div>
          </div>

          <div className="footer-col">
            <h4>Company</h4>
            <Link to="/about">About Us</Link>
            <a href="/#how-it-works">How It Works</a>
            <Link to="/pricing">Pricing</Link>
            <Link to="/support">Contact</Link>
          </div>

          <div className="footer-col">
            <h4>Riders</h4>
            <Link to="/for-riders">How It Works</Link>
            <a href="/#rider-features">Safety</a>
            <Link to="/support">Support</Link>
          </div>

          <div className="footer-col">
            <h4>Drivers</h4>
            <Link to="/for-drivers">How to Register</Link>
            <Link to="/pricing">Subscription Plans</Link>
            <Link to="/for-drivers">Free Trial</Link>
          </div>
        </div>

        <div className="footer-bottom">
          <p>© {new Date().getFullYear()} Gaman. All rights reserved. Built in Hyderabad 🛺</p>
          <div className="footer-bottom-links">
            <a href="https://manayatra.com/privacy" target="_blank" rel="noopener noreferrer">Privacy Policy</a>
            <a href="https://manayatra.com/terms" target="_blank" rel="noopener noreferrer">Terms of Service</a>
            <Link to="/data-deletion">Data Deletion</Link>
          </div>
        </div>
      </div>
    </footer>
  );
}
