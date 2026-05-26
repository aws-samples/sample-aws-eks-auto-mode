import React from 'react';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';

function Hero() {
  return (
    <div className="landing-hero">
      <div className="landing-hero__container">
        <span className="landing-hero__badge">AWS Samples</span>
        <h1 className="landing-hero__title">EKS Auto Mode Samples</h1>
        <p className="landing-hero__tagline">
          Learn EKS Auto Mode through deployable Terraform examples.
          <br />
          Deploy once, explore everything.
        </p>
        <p className="landing-hero__seo-description" style={{fontSize: '1rem', opacity: 0.85, maxWidth: '600px', margin: '0 auto 1.5rem'}}>
          Automate Kubernetes compute, storage, and networking on AWS. Production-ready patterns for GPU, Spot, Graviton, cost optimization, capacity reservations, and more. No add-on management required.
        </p>
        <div className="landing-hero__actions">
          <Link className="landing-hero__btn landing-hero__btn--primary" to="/docs/getting-started">
            Get Started
          </Link>
          <Link className="landing-hero__btn landing-hero__btn--secondary" to="/docs/examples">
            View Examples
          </Link>
        </div>
      </div>
    </div>
  );
}

const features = [
  {
    title: 'Compute Patterns',
    description: 'Graviton, GPU, Spot, and Neuron. Each with a self-contained example explaining the "why" alongside the "how."',
  },
  {
    title: 'Cost Optimization',
    description: 'ODCR targeting, disruption budgets, static capacity pools, and OD/Spot mixed scheduling with overprovision headroom.',
  },
  {
    title: 'Operational Patterns',
    description: '5-layer resource tagging, automated cleanup playbook, CloudWatch Container Insights, and security considerations.',
  },
];

function Features() {
  return (
    <div className="landing-features">
      <div className="landing-features__grid">
        {features.map((f) => (
          <div key={f.title} className="landing-features__card">
            <h3>{f.title}</h3>
            <p>{f.description}</p>
          </div>
        ))}
      </div>
    </div>
  );
}

export default function Home(): React.JSX.Element {
  return (
    <Layout title="Home" description="Learn EKS Auto Mode through deployable Terraform examples">
      <Hero />
      <Features />
    </Layout>
  );
}
