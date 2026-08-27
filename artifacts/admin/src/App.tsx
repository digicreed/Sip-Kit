import { Switch, Route, useLocation, Router as WouterRouter } from "wouter";
import { useEffect, useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";

import { AppLayout } from "@/components/layout/sidebar";
import Login from "@/pages/login";
import Dashboard from "@/pages/dashboard";
import Providers from "@/pages/providers";
import ProviderDetail from "@/pages/provider-detail";
import Usage from "@/pages/usage";
import Install from "@/pages/install";
import NotFound from "@/pages/not-found";

const queryClient = new QueryClient();

function ProtectedRoute({ component: Component }: { component: any }) {
  const [location, setLocation] = useLocation();
  const [isChecking, setIsChecking] = useState(true);

  useEffect(() => {
    const key = localStorage.getItem("adminApiKey");
    if (!key) {
      setLocation("/login");
    } else {
      setIsChecking(false);
    }
  }, [setLocation]);

  if (isChecking) return null;

  return (
    <AppLayout>
      <Component />
    </AppLayout>
  );
}

function Router() {
  return (
    <Switch>
      <Route path="/login" component={Login} />
      <Route path="/install" component={Install} />
      <Route path="/">
        <ProtectedRoute component={Dashboard} />
      </Route>
      <Route path="/providers">
        <ProtectedRoute component={Providers} />
      </Route>
      <Route path="/providers/:providerId">
        <ProtectedRoute component={ProviderDetail} />
      </Route>
      <Route path="/usage">
        <ProtectedRoute component={Usage} />
      </Route>
      <Route component={NotFound} />
    </Switch>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <WouterRouter base={import.meta.env.BASE_URL.replace(/\/$/, "")}>
          <Router />
        </WouterRouter>
        <Toaster />
      </TooltipProvider>
    </QueryClientProvider>
  );
}

export default App;
