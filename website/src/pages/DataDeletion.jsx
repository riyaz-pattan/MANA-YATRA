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

export default function DataDeletion() {
  return (
    <div className="data-deletion-page">
      <div className="container section">
        {/* Hero */}
        <div className="data-deletion-hero">
          <h1 className="section-title">
            Data <span className="gradient-text">Deletion</span>
          </h1>
          <p className="section-subtitle">
            We respect your privacy. Here's how you can delete your account and
            all associated data from Gaman.
          </p>
        </div>

        <div className="data-deletion-content">
          {/* Warning */}
          <div className="deletion-info-box warning">
            <h4>⚠️ Important</h4>
            <p>
              Account deletion is permanent and cannot be undone. Please make
              sure you have no pending rides or outstanding payments before
              proceeding. Once deleted, all your data will be permanently
              removed within 30 days.
            </p>
          </div>

          {/* Steps */}
          <h2
            className="section-title"
            style={{ fontSize: 'var(--font-size-2xl)', marginBottom: 'var(--space-xl)' }}
          >
            How to Delete Your Account
          </h2>

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

          {/* Data info */}
          <div className="deletion-info-box info">
            <h4>📋 What Data Gets Deleted</h4>
            <p>
              When you delete your account, the following data is permanently
              removed from our servers:
            </p>
            <ul>
              <li>Personal profile information (name, email, phone number)</li>
              <li>Ride history and trip details</li>
              <li>Payment and transaction records</li>
              <li>Saved locations and preferences</li>
              <li>
                KYC documents (Aadhaar, Driving License, Profile Photo) — for
                driver accounts
              </li>
              <li>All associated Firebase Authentication credentials</li>
            </ul>
          </div>

          {/* Alternative */}
          <div className="glass-card deletion-alternative">
            <h3>Can't Access the App?</h3>
            <p>
              If you are unable to access the app or your account, you can
              request account deletion by emailing us at{' '}
              <a href="mailto:support@manayatra.com">support@manayatra.com</a>{' '}
              with the subject line "Account Deletion Request". Please include
              your registered phone number and name for verification. We will
              process your request within 7 business days.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
