import './PrivacyPolicy.css';
import AnimatedSection from '../components/AnimatedSection';

export default function PrivacyPolicy() {
  return (
    <div className="privacy-page">
      <header className="privacy-header">
        <div className="container">
          <AnimatedSection>
            <h1>Privacy Policy</h1>
            <p>Last Updated: June 3, 2026</p>
          </AnimatedSection>
        </div>
      </header>

      <section className="privacy-content">
        <div className="container">
          <AnimatedSection>
            <div className="policy-document">
              <h2>1. Introduction</h2>
              <p>
                Welcome to the Gaman Rides Platform ("Company", "we", "our", "us"). We are committed to protecting your personal information and your right to privacy. This Privacy Policy governs the privacy policies and practices of our website, as well as the Gaman Rides platform ecosystem which includes our Rider App, Driver App, and Admin App (collectively, the "Services").
              </p>
              <p>
                By accessing or using our Services, you agree to the collection, use, and disclosure of your personal information as described in this Privacy Policy.
              </p>

              <h2>2. Information We Collect</h2>
              <p>
                We collect information that identifies, relates to, describes, or is reasonably capable of being associated with you. The specific types of data we collect vary depending on whether you are using the Rider App, Driver App, or if you are simply a website visitor.
              </p>
              
              <h3>2.1 Information You Provide to Us</h3>
              <ul>
                <li><strong>Account Registration Data:</strong> When you create an account, we collect your mobile phone number for authentication via One-Time Password (OTP).</li>
                <li><strong>Profile Information:</strong> You may provide a name, email address, and profile photo.</li>
                <li><strong>Driver Verification (KYC) Data:</strong> For Driver App users, we strictly collect Know Your Customer (KYC) documentation for safety and legal compliance. This includes Aadhaar Card details, Driving License, and a live Selfie. This data is securely uploaded and reviewed by our platform administrators.</li>
                <li><strong>Communications:</strong> Any information you provide when you contact customer support, submit disputes, or give ratings and feedback.</li>
              </ul>

              <h3>2.2 Information Collected Automatically</h3>
              <ul>
                <li><strong>Location Data (Riders):</strong> We collect precise location data when the Rider App is running in the foreground to facilitate pickup, drop-off, and fare estimation.</li>
                <li><strong>Location Data (Drivers):</strong> We collect precise and continuous location data (foreground and background) to operate the "SmartTracker" and real-time mapping features. This allows riders to track their incoming driver and ensures accurate route calculation.</li>
                <li><strong>Device Information:</strong> We collect device-specific information, such as hardware model, operating system version, unique device identifiers, and mobile network information.</li>
                <li><strong>Usage Data:</strong> Information about your interaction with our Services, including ride requests, driver bids, timestamps, and app crashes.</li>
              </ul>

              <h2>3. How We Use Your Information</h2>
              <p>We use the collected information for the following business and operational purposes:</p>
              <ul>
                <li><strong>Service Provision:</strong> To create and maintain your account, match riders with drivers via our bidding system, calculate ETAs, and facilitate real-time map navigation.</li>
                <li><strong>Safety and Verification:</strong> To verify driver identities through KYC document reviews by our Admin App, ensuring the safety of all platform users.</li>
                <li><strong>Customer Support:</strong> To resolve disputes, address user inquiries, and monitor ride logs for quality assurance.</li>
                <li><strong>System Improvement:</strong> To analyze usage trends, debug software issues, and optimize our routing and spatial query algorithms (e.g., Geohashing).</li>
              </ul>

              <h2>4. How We Share Your Information</h2>
              <p>We only share your information as absolutely necessary to provide our Services or as required by law.</p>
              <ul>
                <li><strong>Between Riders and Drivers:</strong> During an active ride request, we share the rider's pickup/drop-off location with nearby drivers. Upon bid acceptance, we share your name, live location, and vehicle details to facilitate the ride.</li>
                <li><strong>Service Providers:</strong> We employ third-party services to facilitate our platform, specifically Google Maps Platform (for geocoding and routing) and Firebase (for secure database hosting, storage, and authentication).</li>
                <li><strong>Legal Requirements:</strong> We may disclose your data if required to do so by law, legal process, or governmental request.</li>
              </ul>

              <h2>5. Data Security and Infrastructure</h2>
              <p>
                We implement robust, industry-standard security measures. Our backend relies on Google Firebase. Data in transit is encrypted, and Firestore Security Rules are strictly implemented to ensure users can only access data pertinent to their active sessions or profiles. KYC documents (Aadhaar, Driving License) are stored securely in Cloud Storage and are only accessible by authorized administrators.
              </p>

              <h2>6. Your Rights and Choices</h2>
              <ul>
                <li><strong>Location Permissions:</strong> You may disable location tracking through your device settings, though this will fundamentally limit your ability to use the ride-sharing Services.</li>
                <li><strong>Data Access and Deletion:</strong> You have the right to request access to your data or request account deletion. Please refer to our Data Deletion page or contact support to exercise these rights.</li>
                <li><strong>Correction:</strong> You can update your profile information within the app settings.</li>
              </ul>

              <h2>7. Changes to This Privacy Policy</h2>
              <p>
                We may update this Privacy Policy from time to time. The updated version will be indicated by an updated "Last Updated" date and the updated version will be effective as soon as it is accessible. We encourage you to review this Privacy Policy frequently to be informed of how we are protecting your information.
              </p>

              <h2>8. Contact Us</h2>
              <p>
                If you have questions, comments, or concerns about this policy or our privacy practices, please contact our Data Protection Officer at:
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
