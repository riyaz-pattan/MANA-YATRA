import './PricingCards.css';

const plans = [
  {
    name: '1 Day',
    price: '₹20',
    perDay: '₹20/day',
    badge: null,
    featured: false,
    features: ['Full platform access', 'See all ride requests', 'Set your own price', 'Direct UPI payments'],
  },
  {
    name: '7 Days',
    price: '₹133',
    perDay: '₹19/day',
    badge: 'Save ₹7',
    featured: false,
    features: ['Everything in 1 Day', 'Save ₹7 vs daily', 'No interruptions', 'Priority support'],
  },
  {
    name: '30 Days',
    price: '₹540',
    perDay: '₹18/day',
    badge: 'Best Value ⭐',
    featured: true,
    features: ['Everything in 7 Days', 'Save ₹60 vs daily', 'Lowest per-day cost', 'Priority support'],
  },
];

export default function PricingCards() {
  return (
    <div>
      <div className="pricing-cards-grid">
        {plans.map((plan, i) => (
          <div className={`pricing-card ${plan.featured ? 'featured' : ''}`} key={i}>
            {plan.badge && (
              <div className="card-badge">
                <span className="badge-zero">{plan.badge}</span>
              </div>
            )}
            <div className="plan-name">{plan.name}</div>
            <div className="plan-price">{plan.price}</div>
            <div className="plan-per-day">{plan.perDay}</div>
            <ul className="plan-features">
              {plan.features.map((f, j) => (
                <li key={j}>{f}</li>
              ))}
            </ul>
            <a
              href="https://play.google.com/store"
              target="_blank"
              rel="noopener noreferrer"
              className={`btn ${plan.featured ? 'btn-primary' : 'btn-outline'}`}
            >
              Get Started
            </a>
          </div>
        ))}
      </div>

      <div className="free-trial-banner">
        <div className="trial-text">
          <h3>New driver? Start your 7-day FREE trial today.</h3>
          <p>No payment. No credit card. Full access.</p>
        </div>
        <a
          href="https://play.google.com/store"
          target="_blank"
          rel="noopener noreferrer"
          className="btn"
        >
          Start Free Trial →
        </a>
      </div>
    </div>
  );
}
