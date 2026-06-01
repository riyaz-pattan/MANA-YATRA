import './DataDeletion.css';

const deletionSteps = [
  {
    title: 'Open the Gaman App',
    desc: 'Launch the Gaman (Rider) or Gaman Driver app on your device and make sure you are logged in to the account you wish to delete.',
  },
  {
    title: 'Navigate to Settings',
    desc: 'Tap on your profile icon or menu, then select "Settings" from the navigation options.',
  },
  {
    title: 'Select "Delete Account"',
    desc: 'Scroll down to find the "Delete Account" option. Tap on it to begin the account deletion process.',
  },
  {
    title: 'Confirm Your Identity',
    desc: 'You will be asked to re-authenticate using your registered phone number via OTP for security verification.',
  },
  {
    title: 'Confirm Deletion',
    desc: 'Review the information about what data will be deleted, then confirm your decision. Your account will be scheduled for permanent deletion.',
  },
];

const deletedData = [
  'Personal profile information (name, email, phone number)',
  'Ride history and trip details',
  'Payment and transaction records',
  'Saved locations and preferences',
  'KYC documents (Aadhaar, Driving License, Profile Photo) — for driver accounts',
  'All associated Firebase Authentication credentials',
];

export default function DataDeletion() {
  return (
    <div className="data-deletion-page">
      {/* Hero Section */}
      <section className="deletion-hero">
        <div className="container">
          <span className="badge-primary">🔒 Your Privacy Matters</span>
          <h1>Data Deletion</h1>
          <p className="deletion-hero-subtitle">
            We respect your privacy. Here's how you can delete your account and all associated data from Gaman.
          </p>
        </div>
      </section>

      {/* Content Section */}
      <section className="section deletion-content-section">
        <div className="container">
          <div className="deletion-content">
            {/* Warning Box */}
            <div className="deletion-warning-box">
              <div className="deletion-warning-icon">⚠️</div>
              <div>
                <h4>Important — This Action is Permanent</h4>
                <p>
                  Account deletion cannot be undone. Please make sure you have no pending rides or outstanding payments before proceeding. Once deleted, all your data will be permanently removed from our servers within 30 days.
                </p>
              </div>
            </div>

            {/* Steps */}
            <div className="deletion-steps-block">
              <h2>How to Delete Your Account</h2>
              <div className="deletion-steps-list">
                {deletionSteps.map((step, i) => (
                  <div className="deletion-step" key={i}>
                    <div className="deletion-step-num">{i + 1}</div>
                    <div className="deletion-step-content">
                      <h3>{step.title}</h3>
                      <p>{step.desc}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Data Inventory */}
            <div className="deletion-data-block">
              <h2>What Data Gets Deleted</h2>
              <p className="deletion-data-intro">
                When you delete your account, the following data is permanently removed from our servers:
              </p>
              <ul className="deletion-data-list">
                {deletedData.map((item, i) => (
                  <li key={i}>
                    <span className="deletion-check">✕</span>
                    {item}
                  </li>
                ))}
              </ul>
            </div>

            {/* Alternative Contact */}
            <div className="deletion-alternative card-light">
              <div className="deletion-alt-icon">📧</div>
              <h3>Can't Access the App?</h3>
              <p>
                If you are unable to access the app or your account, you can request account deletion by emailing us at{' '}
                <a href="mailto:support@wetechspire.com">support@wetechspire.com</a>{' '}
                with the subject line "Account Deletion Request". Please include your registered phone number and name for verification.
              </p>
              <p className="deletion-alt-timeline">
                We will process your request within <strong>7 business days</strong>.
              </p>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
