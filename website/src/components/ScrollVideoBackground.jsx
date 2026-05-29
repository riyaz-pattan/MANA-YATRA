import { useRef, useEffect } from 'react';
import './ScrollVideoBackground.css';

export default function ScrollVideoBackground({ videoSrc }) {
  const containerRef = useRef(null);
  const videoRef = useRef(null);

  useEffect(() => {
    if (!videoSrc || !videoRef.current) return;

    const video = videoRef.current;

    const handleScroll = () => {
      const container = containerRef.current;
      if (!container || !video.duration) return;

      const rect = container.getBoundingClientRect();
      const scrollableHeight = container.offsetHeight - window.innerHeight;
      const scrollProgress = Math.min(
        Math.max(-rect.top / scrollableHeight, 0),
        1
      );

      video.currentTime = scrollProgress * video.duration;
    };

    video.addEventListener('loadedmetadata', () => {
      video.pause();
      handleScroll();
    });

    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, [videoSrc]);

  return (
    <div className="scroll-video-container" ref={containerRef}>
      <div className="scroll-video-sticky">
        {videoSrc ? (
          <video ref={videoRef} muted playsInline preload="auto">
            <source src={videoSrc} type="video/mp4" />
          </video>
        ) : (
          <div className="scroll-video-placeholder">
            <div className="placeholder-graphic">
              <div className="placeholder-ring" />
            </div>
          </div>
        )}

        <div className="scroll-video-overlay" />

        <div className="scroll-video-content">
          <h1 className="animate-fade-in-up">
            Move with <span className="gradient-text">Gaman</span>
          </h1>
          <p className="animate-fade-in-up delay-2">
            Zero commission rides. Fair prices for riders. 100% earnings for
            drivers. Redefining urban mobility in India.
          </p>
          <div className="hero-badges animate-fade-in-up delay-3">
            <span className="hero-badge">🚗 Zero Commission</span>
            <span className="hero-badge">💰 Fair Prices</span>
            <span className="hero-badge">🔒 Safe Rides</span>
          </div>
        </div>

        <div className="scroll-indicator">
          <span>Scroll to explore</span>
          <div className="scroll-indicator-arrow" />
        </div>
      </div>
    </div>
  );
}
