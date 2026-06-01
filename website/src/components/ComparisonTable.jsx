import './ComparisonTable.css';

const rows = [
  { feature: 'Commission per ride', ola: '20–30%', rapido: '15–20%', gaman: '0%', gamanGood: true },
  { feature: 'Driver cost model', ola: 'Per-ride cut', rapido: 'Per-ride cut', gaman: '₹20/day flat', gamanGood: true },
  { feature: 'Driver gets (₹100 fare)', ola: '₹70–80', rapido: '₹80–85', gaman: '₹100', gamanGood: true },
  { feature: 'Monthly savings', ola: '—', rapido: '—', gaman: '₹4,000–9,000+', gamanGood: true },
  { feature: 'Surge pricing', ola: 'Yes', rapido: 'Yes', gaman: 'No', gamanGood: true, olaBad: true, rapidoBad: true },
  { feature: 'Set your own price', ola: 'No', rapido: 'No', gaman: 'Yes', gamanGood: true, olaBad: true, rapidoBad: true },
  { feature: 'Direct payment', ola: 'No', rapido: 'No', gaman: 'Yes', gamanGood: true, olaBad: true, rapidoBad: true },
];

export default function ComparisonTable() {
  return (
    <div className="comparison-table">
      <table>
        <thead>
          <tr>
            <th></th>
            <th>Other Cab Apps</th>
            <th>Other Bike Apps</th>
            <th className="col-gaman">
              Gaman
              <span className="table-badge">
                <span className="badge-zero">Our Platform</span>
              </span>
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i}>
              <td className="feature-name">{row.feature}</td>
              <td className={row.olaBad ? 'val-bad' : 'val-neutral'}>{row.ola}</td>
              <td className={row.rapidoBad ? 'val-bad' : 'val-neutral'}>{row.rapido}</td>
              <td className={`col-gaman ${row.gamanGood ? 'val-good' : ''}`}>{row.gaman}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
