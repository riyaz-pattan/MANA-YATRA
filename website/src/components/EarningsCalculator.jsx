import { useState } from 'react';
import './EarningsCalculator.css';

export default function EarningsCalculator() {
  const [rides, setRides] = useState(15);
  const [fare, setFare] = useState(100);

  const days = 30;
  const otherAppCut = 0.25; // avg 25% commission
  const gamanSubscription = 20; // 20 rupees per day

  const totalMonthly = rides * fare * days;
  const otherAppEarnings = Math.round(totalMonthly * (1 - otherAppCut));
  const gamanEarnings = totalMonthly - (gamanSubscription * days);
  const savings = gamanEarnings - otherAppEarnings;

  return (
    <div className="earnings-calc">
      <h3>Earnings Calculator</h3>
      <p>See how much more you earn with Gaman vs other platforms.</p>

      <div className="calc-sliders">
        <div className="calc-slider-group">
          <label>
            How many rides do you do per day?{' '}
            <span className="slider-value">{rides}</span>
          </label>
          <input
            type="range"
            min="5"
            max="30"
            value={rides}
            onChange={(e) => setRides(Number(e.target.value))}
          />
        </div>
        <div className="calc-slider-group">
          <label>
            Average fare per ride?{' '}
            <span className="slider-value">₹{fare}</span>
          </label>
          <input
            type="range"
            min="60"
            max="200"
            step="10"
            value={fare}
            onChange={(e) => setFare(Number(e.target.value))}
          />
        </div>
      </div>

      <div className="calc-results">
        <div className="calc-result-card other">
          <div className="result-label">Your earnings on other platforms</div>
          <div className="result-value">₹{otherAppEarnings.toLocaleString('en-IN')}</div>
          <div className="result-sub">per month (after ~25% cut)</div>
        </div>
        <div className="calc-result-card gaman">
          <div className="result-label">Your earnings on Gaman</div>
          <div className="result-value">₹{gamanEarnings.toLocaleString('en-IN')}</div>
          <div className="result-sub">per month (₹20/day flat)</div>
        </div>
        <div className="calc-result-card savings">
          <div className="result-label">You save</div>
          <div className="result-value">₹{savings.toLocaleString('en-IN')}</div>
          <div className="result-sub">more per month with Gaman</div>
        </div>
      </div>
    </div>
  );
}
