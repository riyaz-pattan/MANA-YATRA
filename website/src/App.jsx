import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import ScrollToTop from './components/ScrollToTop';
import Home from './pages/Home';
import ForDrivers from './pages/ForDrivers';
import ForRiders from './pages/ForRiders';
import HowItWorks from './pages/HowItWorks';
import Pricing from './pages/Pricing';
import About from './pages/About';
import Support from './pages/Support';
import DataDeletion from './pages/DataDeletion';

export default function App() {
  return (
    <BrowserRouter>
      <ScrollToTop />
      <Navbar />
      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/for-drivers" element={<ForDrivers />} />
          <Route path="/for-riders" element={<ForRiders />} />
          <Route path="/how-it-works" element={<HowItWorks />} />
          <Route path="/pricing" element={<Pricing />} />
          <Route path="/about" element={<About />} />
          <Route path="/support" element={<Support />} />
          <Route path="/data-deletion" element={<DataDeletion />} />
        </Routes>
      </main>
      <Footer />
    </BrowserRouter>
  );
}
