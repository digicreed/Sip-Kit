import { useLocation, Link } from "wouter";
import { LayoutDashboard, Users, Activity, LogOut, Shield } from "lucide-react";
import { cn } from "@/lib/utils";

const navItems = [
  { name: "Dashboard", href: "/", icon: LayoutDashboard },
  { name: "Providers", href: "/providers", icon: Users },
  { name: "Usage", href: "/usage", icon: Activity },
];

export function Sidebar() {
  const [location, setLocation] = useLocation();

  const handleLogout = () => {
    localStorage.removeItem("adminApiKey");
    setLocation("/login");
  };

  return (
    <div className="flex flex-col w-64 border-r border-border bg-sidebar text-sidebar-foreground h-screen sticky top-0 shrink-0">
      <div className="h-14 flex items-center px-4 border-b border-sidebar-border">
        <Shield className="w-5 h-5 text-primary mr-2" />
        <span className="font-semibold text-lg tracking-tight">SipKit Ops</span>
      </div>

      <div className="flex-1 py-4 flex flex-col gap-1 px-3">
        {navItems.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className={cn(
              "flex items-center gap-3 px-3 py-2 rounded-md text-sm transition-colors",
              location === item.href || (item.href !== "/" && location.startsWith(item.href))
                ? "bg-sidebar-accent text-sidebar-accent-foreground font-medium"
                : "text-sidebar-foreground/70 hover:bg-sidebar-accent/50 hover:text-sidebar-foreground"
            )}
            data-testid={`nav-${item.name.toLowerCase()}`}
          >
            <item.icon className="w-4 h-4" />
            {item.name}
          </Link>
        ))}
      </div>

      <div className="p-4 border-t border-sidebar-border">
        <button
          onClick={handleLogout}
          className="flex items-center gap-3 px-3 py-2 w-full rounded-md text-sm text-sidebar-foreground/70 hover:bg-sidebar-accent/50 hover:text-sidebar-foreground transition-colors"
          data-testid="nav-logout"
        >
          <LogOut className="w-4 h-4" />
          Logout
        </button>
      </div>
    </div>
  );
}

export function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen w-full bg-background text-foreground">
      <Sidebar />
      <main className="flex-1 overflow-auto">
        <div className="p-8 max-w-6xl mx-auto">{children}</div>
      </main>
    </div>
  );
}
