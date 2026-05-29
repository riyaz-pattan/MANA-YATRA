import './Support.css';

export default function Support() {
  return (
    <div className="support-page">
      <div className="container section">
        {/* Hero */}
        <div className="support-hero">
          <h1 className="section-title">
            How Can We <span className="gradient-text">Help?</span>
          </h1>
          <p className="section-subtitle">
            We're here 24/7 to assist you with anything related to your Gaman
            experience. Reach out through any of the channels below.
          </p>
        </div>

        {/* Contact Cards */}
        <div className="support-grid">
          <div className="glass-card support-card">
            <div className="support-card-icon">📧</div>
            <h3>Email Support</h3>
            <p>
              Send us a detailed message and our team will get back to you
              within 24 hours.
            </p>
            <a href="mailto:support@manayatra.com">support@manayatra.com</a>
          </div>

          <div className="glass-card support-card">
            <div className="support-card-icon">📱</div>
            <h3>In-App Support</h3>
            <p>
              Use the "Report Issue" feature directly in the Gaman app for the
              fastest response time.
            </p>
            <span style={{ color: 'var(--color-accent-primary)', fontSize: 'var(--font-size-sm)', fontWeight: 600 }}>
              Open Gaman App → Settings → Support
            </span>
          </div>

          <div className="glass-card support-card">
            <div className="support-card-icon">🕐</div>
            <h3>Response Time</h3>
            <p>
              We aim to respond to all queries within 24 hours. Urgent safety
              issues are prioritized immediately.
            </p>
            <span style={{ color: 'var(--color-accent-primary)', fontSize: 'var(--font-size-sm)', fontWeight: 600 }}>
              Average: Under 12 hours
            </span>
          </div>
        </div>

        {/* Contact Form */}
        <div className="support-form-section">
          <h2>
            Send Us a <span className="gradient-text">Message</span>
          </h2>
          <p>
            Fill out the form below and we'll get back to you as soon as
            possible.
          </p>
          <form
            className="support-form"
            onSubmit={(e) => {
              e.preventDefault();
              alert('Thank you! Your message has been submitted. We will get back to you shortly.');
            }}
          >
            <div className="form-row">
              <div className="form-group">
                <label htmlFor="support-name">Full Name</label>
                <input
                  type="text"
                  id="support-name"
                  placeholder="Enter your full name"
                  required
                />
              </div>
              <div className="form-group">
                <label htmlFor="support-email">Email Address</label>
                <input
                  type="email"
                  id="support-email"
                  placeholder="you@example.com"
                  required
                />
              </div>
            </div>

            <div className="form-row">
              <div className="form-group">
                <label htmlFor="support-phone">Phone Number</label>
                <input
                  type="tel"
                  id="support-phone"
                  placeholder="+91 XXXXX XXXXX"
                />
              </div>
              <div className="form-group">
                <label htmlFor="support-type">Issue Type</label>
                <select id="support-type" required>
                  <option value="">Select an issue</option>
                  <option value="ride">Ride Issue</option>
                  <option value="payment">Payment Issue</option>
                  <option value="account">Account Issue</option>
                  <option value="driver">Driver Complaint</option>
                  <option value="safety">Safety Concern</option>
                  <option value="other">Other</option>
                </select>
              </div>
            </div>

            <div className="form-group">
              <label htmlFor="support-message">Describe Your Issue</label>
              <textarea
                id="support-message"
                placeholder="Please provide as much detail as possible about your issue..."
                required
              />
            </div>

            <button type="submit" className="btn btn-primary" style={{ alignSelf: 'flex-start' }}>
              Submit Request
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}
