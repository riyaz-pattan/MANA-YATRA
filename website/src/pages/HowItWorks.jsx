import ComparisonTable from '../components/ComparisonTable';
import './HowItWorks.css';

const riderFlow = [
  {
    number: 1,
    icon: '📱',
    title: 'Open the Gaman App',
    desc: 'Launch the app and you\'re greeted with a clean map view. Your current location is auto-detected.',
  },
  {
    number: 2,
    icon: '📍',
    title: 'Set Pickup & Drop-off',
    desc: 'Enter where you want to go. Smart auto-complete makes it fast. Confirm your pickup location on the map.',
  },
  {
    number: 3,
    icon: '📡',
    title: 'Request is Broadcasted',
    desc: 'Your ride request goes out to all verified drivers nearby. They can see the trip distance, route, and your pickup point.',
  },
  {
    number: 4,
    icon: '💰',
    title: 'Receive Driver Bids',
    desc: 'Drivers compete by placing their best price. You see each bid with the driver\'s rating, vehicle info, and estimated arrival.',
  },
  {
    number: 5,
    icon: '✅',
    title: 'Accept a Bid',
    desc: 'Choose the bid that works for you — cheapest, highest-rated, or closest. The driver is confirmed instantly.',
  },
  {
    number: 6,
    icon: '🔐',
    title: 'Verify with OTP',
    desc: 'Share the ride OTP with your driver for a secure start. Your trip is now tracked in real-time.',
  },
  {
    number: 7,
    icon: '🚗',
    title: 'Enjoy Your Ride',
    desc: 'Track the route live. Share your ride status with contacts via the SOS feature for added safety.',
  },
  {
    number: 8,
    icon: '⭐',
    title: 'Pay & Rate',
    desc: 'Pay via cash or UPI directly to the driver. Rate your experience to keep the community trusted and fair.',
  },
];

const driverFlow = [
  {
    number: 1,
    icon: '📲',
    title: 'Download & Register',
    desc: 'Install Gaman Driver from the Play Store. Sign up with your phone number and complete KYC verification.',
  },
  {
    number: 2,
    icon: '🟢',
    title: 'Go Online',
    desc: 'Toggle your status to "Online" from the dashboard. The Smart Tracker starts broadcasting your availability.',
  },
  {
    number: 3,
    icon: '🔔',
    title: 'Get Ride Requests',
    desc: 'Receive nearby ride requests with full details — pickup, drop-off, distance, and route preview.',
  },
  {
    number: 4,
    icon: '💸',
    title: 'Place Your Bid',
    desc: 'Set your own fair price for the ride. No algorithm decides your earnings — you\'re in full control.',
  },
  {
    number: 5,
    icon: '✅',
    title: 'Bid Accepted',
    desc: 'When the rider picks your bid, you get confirmed instantly. Navigate to the pickup point using built-in maps.',
  },
  {
    number: 6,
    icon: '🔑',
    title: 'Verify Rider OTP',
    desc: 'Enter the rider\'s OTP to start the trip. This ensures you\'re picking up the right person.',
  },
  {
    number: 7,
    icon: '🛣️',
    title: 'Complete the Trip',
    desc: 'Follow the navigation to the drop-off point. The ride is tracked in real-time for safety and transparency.',
  },
  {
    number: 8,
    icon: '💰',
    title: 'Get Paid 100%',
    desc: 'Receive the full fare via cash or UPI — zero commission deducted. Rate the rider and you\'re ready for the next trip.',
  },
];

export default function HowItWorks() {
  return (
    <div className="how-it-works-page">
      {/* Hero Section */}
      <section className="section hiw-hero">
        <div className="container">
          <span className="badge-purple">📖 Understanding Gaman</span>
          <h1>
            How <span className="hiw-gradient-text">Gaman</span> Works
          </h1>
          <p className="hiw-hero-sub">
            A completely transparent ride-hailing platform where drivers bid, riders choose,
            and everyone wins. No commission, no surge, no nonsense.
          </p>
          <div className="hiw-hero-highlights">
            <div className="hiw-highlight">
              <span className="hiw-highlight-icon">🏷️</span>
              <span>Zero Commission</span>
            </div>
            <div className="hiw-highlight">
              <span className="hiw-highlight-icon">💰</span>
              <span>Bid-Based Pricing</span>
            </div>
            <div className="hiw-highlight">
              <span className="hiw-highlight-icon">🛡️</span>
              <span>Verified & Safe</span>
            </div>
          </div>
        </div>
      </section>

      {/* Rider Flow Section */}
      <section className="section hiw-rider-flow">
        <div className="container">
          <span className="badge-purple">🚶 Rider Journey</span>
          <h2 className="hiw-section-title">
            How Riders <span className="hiw-gradient-text">Book a Ride</span>
          </h2>
          <p className="hiw-section-subtitle">
            From opening the app to reaching your destination — here's the complete rider experience.
          </p>
          <div className="hiw-flow-grid">
            {riderFlow.map((step) => (
              <div className="hiw-flow-card" key={step.number}>
                <div className="hiw-flow-number">{step.number}</div>
                <div className="hiw-flow-icon">{step.icon}</div>
                <h3>{step.title}</h3>
                <p>{step.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Driver Flow Section */}
      <section className="section hiw-driver-flow">
        <div className="container">
          <span className="badge-green">🚗 Driver Journey</span>
          <h2 className="hiw-section-title hiw-title-dark">
            How Drivers <span className="hiw-gradient-text">Earn</span>
          </h2>
          <p className="hiw-section-subtitle hiw-subtitle-dark">
            From registration to your first completed ride — here's how drivers earn 100% on Gaman.
          </p>
          <div className="hiw-flow-grid">
            {driverFlow.map((step) => (
              <div className="hiw-flow-card hiw-flow-card-white" key={step.number}>
                <div className="hiw-flow-number hiw-flow-number-green">{step.number}</div>
                <div className="hiw-flow-icon">{step.icon}</div>
                <h3>{step.title}</h3>
                <p>{step.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Comparison Section */}
      <section className="section hiw-comparison">
        <div className="container">
          <h2 className="hiw-section-title hiw-title-white">
            Gaman vs <span className="hiw-gradient-text">Others</span>
          </h2>
          <p className="hiw-section-subtitle hiw-subtitle-white">
            See how Gaman stacks up against traditional ride-hailing platforms.
          </p>
          <ComparisonTable />
        </div>
      </section>

      {/* Download CTA Section */}
      <section className="section hiw-cta">
        <div className="container">
          <h2>Experience It Yourself</h2>
          <p>
            Download Gaman today — whether you ride or drive, the platform is built for you.
          </p>
          <div className="hiw-cta-buttons">
            <a
              href="https://play.google.com/store"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-dark"
            >
              📱 Get Gaman for Riders
            </a>
            <a
              href="https://play.google.com/store"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-dark"
            >
              🚗 Get Gaman for Drivers
            </a>
          </div>
        </div>
      </section>
    </div>
  );
}
