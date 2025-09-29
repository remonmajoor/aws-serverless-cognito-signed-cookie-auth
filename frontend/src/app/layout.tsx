import "./globals.css";
import type { Metadata } from "next";
import ProfileNav from "@/components/ProfileNav";

export const metadata: Metadata = {
  title: "Serverless cognito cloudfront signed cookie auth infrastructure",
  description: "Serverless cognito cloudfront signed cookie auth infrastructure",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <main className="mx-auto max-w-6xl px-5 py-8">
          <div className="grid gap-8 lg:grid-cols-[280px_minmax(0,1fr)]">
            {/* Left: sticky profile + nav */}
            <ProfileNav />
            {/* Right: page content */}
            <section className="min-w-0">
              {children}
            </section>
          </div>
        </main>
      </body>
    </html>
  );
}