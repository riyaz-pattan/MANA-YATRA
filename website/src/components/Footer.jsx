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
              <span>Gaman</span>
            </div>
            <p>
              Your reliable partner for daily commutes. Zero commission rides,
              fair prices, and 100% earnings for drivers. Moving India forward,
              one ride at a time.
            </p>
          </div>

          <div className="footer-col">
            <h4>Company</h4>
            <Link to="/">Home</Link>
            <a href="/#mission">Our Mission</a>
            <a href="/#how-it-works">How It Works</a>
            <a href="/#faq">FAQ</a>
          </div>

          <div className="footer-col">
            <h4>Legal</h4>
            <a href="https://manayatra.com/terms" target="_blank" rel="noopener noreferrer">
              Terms of Service
            </a>
            <a href="https://manayatra.com/privacy" target="_blank" rel="noopener noreferrer">
              Privacy Policy
            </a>
            <Link to="/data-deletion">Data Deletion</Link>
          </div>

          <div className="footer-col">
            <h4>Support</h4>
            <Link to="/support">Help Center</Link>
            <a href="mailto:support@manayatra.com">Email Us</a>
          </div>
        </div>

        <div className="footer-bottom">
          <p>&copy; {new Date().getFullYear()} Gaman. All rights reserved.</p>
          <div className="footer-social">
            <a href="#" aria-label="Twitter">𝕏</a>
            <a href="#" aria-label="Instagram">📷</a>
            <a href="#" aria-label="LinkedIn">in</a>
          </div>
        </div>
      </div>
    </footer>
  );
}
