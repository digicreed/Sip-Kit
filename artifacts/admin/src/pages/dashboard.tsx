import { useGetAdminSummary } from "@workspace/api-client-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Activity, PhoneCall, Server, Key, PhoneMissed, Users } from "lucide-react";

export default function Dashboard() {
  const { data: summary, isLoading, error } = useGetAdminSummary();

  if (isLoading) {
    return <div className="space-y-6 animate-pulse">
      <div className="h-8 w-48 bg-muted rounded"></div>
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        {[1,2,3,4,5,6].map(i => (
          <div key={i} className="h-32 bg-muted rounded-xl"></div>
        ))}
      </div>
    </div>;
  }

  if (error || !summary) {
    return <div className="text-destructive">Failed to load summary statistics.</div>;
  }

  const statCards = [
    {
      title: "Total Providers",
      value: summary.totalProviders,
      icon: Users,
      testId: "stat-providers"
    },
    {
      title: "Active Licenses",
      value: summary.activeLicenses,
      icon: Key,
      testId: "stat-active-licenses"
    },
    {
      title: "Revoked Licenses",
      value: summary.revokedLicenses,
      icon: PhoneMissed,
      testId: "stat-revoked-licenses",
      className: "text-muted-foreground"
    },
    {
      title: "Total Call Minutes",
      value: summary.totalCallMinutes.toLocaleString(),
      icon: Activity,
      testId: "stat-call-minutes"
    },
    {
      title: "Total Registrations",
      value: summary.totalRegistrations.toLocaleString(),
      icon: Server,
      testId: "stat-registrations"
    },
    {
      title: "Total Calls Placed",
      value: summary.totalCallsPlaced.toLocaleString(),
      icon: PhoneCall,
      testId: "stat-calls-placed"
    }
  ];

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
        <p className="text-muted-foreground mt-2">Platform overview and aggregate usage statistics.</p>
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        {statCards.map((stat, i) => (
          <Card key={i} className={stat.className}>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">
                {stat.title}
              </CardTitle>
              <stat.icon className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold" data-testid={stat.testId}>
                {stat.value}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
