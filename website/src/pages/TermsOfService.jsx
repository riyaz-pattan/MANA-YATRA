import './TermsOfService.css';
import AnimatedSection from '../components/AnimatedSection';

export default function TermsOfService() {
  return (
    <div className="terms-page">
      <header className="terms-header">
        <div className="container">
          <AnimatedSection>
            <h1>Terms of Service</h1>
            <p>Last Updated: June 3, 2026</p>
          </AnimatedSection>
        </div>
      </header>

      <section className="terms-content">
        <div className="container">
          <AnimatedSection>
            <div className="terms-document">
              <h2>1. Contractual Relationship</h2>
              <p>
                These Terms of Service ("Terms") govern the access or use by you, an individual, of applications, websites, content, products, and services (the "Services") made available by Gaman Rides ("Company", "we", "our", "us"). 
              </p>
              <p>
                PLEASE READ THESE TERMS CAREFULLY BEFORE ACCESSING OR USING THE SERVICES. By accessing or using our Rider App, Driver App, Admin App, or Website, you confirm your agreement to be bound by these Terms.
              </p>

              <h2>2. The Services</h2>
              <p>
                The Services comprise a technology platform that connects passengers ("Riders") with independent providers of transportation services ("Drivers"). 
              </p>
              <p>
                <strong>GAMAN RIDES DOES NOT PROVIDE TRANSPORTATION SERVICES, AND WE ARE NOT A TRANSPORTATION CARRIER.</strong> We offer a peer-to-peer bidding platform where Riders and Drivers can negotiate and agree upon a fare. Drivers are independent third-party contractors and are not employees, partners, or agents of Gaman Rides.
              </p>

              <h2>3. User Accounts and Conduct</h2>
              <h3>3.1 Account Creation</h3>
              <p>
                To use the Services, you must register for and maintain an active user account. You must be at least 18 years of age to obtain an account. Account registration requires you to submit certain personal information, such as your name and mobile phone number for OTP verification.
              </p>

              <h3>3.2 Driver Obligations and KYC</h3>
              <p>
                Drivers must complete a strict Know Your Customer (KYC) verification process, which includes submitting a valid Aadhaar Card, Driving License, and a live selfie. Drivers agree to maintain their vehicles in a safe, legally compliant condition and possess all necessary commercial insurance and permits required by law.
              </p>

              <h3>3.3 User Conduct</h3>
              <p>
                You may not authorize third parties to use your account. You agree to comply with all applicable laws when using the Services, and you may only use the Services for lawful purposes. You will not cause nuisance, annoyance, inconvenience, or property damage to any other party (Rider or Driver).
              </p>

              <h2>4. The Bidding System and Payment</h2>
              <p>
                Unlike traditional ride-hailing platforms, Gaman Rides utilizes a real-time <strong>Bidding System</strong>. 
              </p>
              <ul>
                <li><strong>Riders:</strong> Submit a ride request detailing the pickup and drop-off locations.</li>
                <li><strong>Drivers:</strong> View nearby requests and submit customized fare bids based on distance, traffic, and personal preference.</li>
                <li><strong>Agreement:</strong> The Rider reviews the incoming bids and selects their preferred Driver and fare. Once accepted, the fare is locked.</li>
              </ul>
              <p>
                Riders are responsible for paying the agreed-upon fare directly to the Driver upon completion of the ride. Gaman Rides operates on a zero-commission model for individual rides, though Drivers may be subject to platform subscription fees.
              </p>

              <h2>5. Disclaimers and Limitation of Liability</h2>
              <h3>5.1 Disclaimer</h3>
              <p>
                THE SERVICES ARE PROVIDED "AS IS" AND "AS AVAILABLE." GAMAN RIDES DISCLAIMS ALL REPRESENTATIONS AND WARRANTIES, EXPRESS, IMPLIED OR STATUTORY, NOT EXPRESSLY SET OUT IN THESE TERMS. WE DO NOT GUARANTEE THE QUALITY, SUITABILITY, SAFETY, OR ABILITY OF THIRD-PARTY DRIVERS. YOU AGREE THAT THE ENTIRE RISK ARISING OUT OF YOUR USE OF THE SERVICES REMAINS SOLELY WITH YOU.
              </p>

              <h3>5.2 Limitation of Liability</h3>
              <p>
                GAMAN RIDES SHALL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, PUNITIVE OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, LOST DATA, PERSONAL INJURY OR PROPERTY DAMAGE RELATED TO, IN CONNECTION WITH, OR OTHERWISE RESULTING FROM ANY USE OF THE SERVICES.
              </p>

              <h2>6. Termination</h2>
              <p>
                We may restrict you from accessing or using the Services, or any part of them, immediately, without notice, in circumstances where we reasonably suspect that: (i) you have, or are likely to, breach these Terms; or (ii) you have engaged in fraudulent or illegal activity.
              </p>

              <h2>7. Governing Law</h2>
              <p>
                Except as otherwise set forth in these Terms, these Terms shall be exclusively governed by and construed in accordance with the laws of India. Any disputes arising out of these Terms shall be subject to the exclusive jurisdiction of the courts located in Andhra Pradesh, India.
              </p>

              <h2>8. Contact Us</h2>
              <p>
                For any legal inquiries or disputes regarding these Terms of Service, please contact us at:
              </p>
              <address>
                <strong>Gaman Rides Legal Department</strong><br />
                Email: wetechspire@gmail.com<br />
                Ongole, Andhra Pradesh, India
              </address>
            </div>
          </AnimatedSection>
        </div>
      </section>
    </div>
  );
}
