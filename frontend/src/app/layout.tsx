import type { Metadata } from "next";
import "./globals.css";
import { ThemeProvider } from "@/components/theme-provider";
import DynamicBackground from "@/components/dynamic-background";
import { AppSidebar } from "@/components/app-sidebar"
import {
  SidebarInset,
  SidebarProvider,
} from "@/components/ui/sidebar"
import { HoverProvider } from "@/components/wow/hover-provider";

export const metadata: Metadata = {
  title: "WoW PvP Meta",
  description: "PvP Insights for WoW Arena / Shuffle / RBG.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="min-h-screen bg-background text-foreground antialiased">
        <ThemeProvider attribute="class" defaultTheme="dark">
          <HoverProvider>
            <SidebarProvider>
              <AppSidebar />
              <SidebarInset>
                <main>
                  {children}
                </main>
                <DynamicBackground />
              </SidebarInset>
            </SidebarProvider>
          </HoverProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
