import "./globals.css";
import type { Metadata } from "next";
import { ServiceWorkerRegister } from "@/components/service-worker-register";

export const metadata: Metadata = {
  title: "Vadio Cellar",
  description: "Gestao de adega Vadio",
  manifest: "/manifest.webmanifest"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt">
      <body>
        <ServiceWorkerRegister />
        {children}
      </body>
    </html>
  );
}
