import { useState, useMemo } from "react";
import { 
  useGetUsage, 
  useListProviders,
  getGetUsageQueryKey 
} from "@workspace/api-client-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Activity, PhoneCall, Server } from "lucide-react";
import { 
  BarChart, 
  Bar, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  ResponsiveContainer,
  Legend
} from "recharts";

export default function Usage() {
  const [providerId, setProviderId] = useState<string>("all");
  const [fromDate, setFromDate] = useState<string>(() => {
    const d = new Date();
    d.setDate(d.getDate() - 30);
    return d.toISOString().slice(0, 10);
  });
  const [toDate, setToDate] = useState<string>(() => {
    return new Date().toISOString().slice(0, 10);
  });
  
  const { data: providers } = useListProviders();
  
  const queryParams = {
    ...(providerId !== "all" ? { providerId } : {}),
    from: fromDate ? `${fromDate}T00:00:00.000Z` : undefined,
    to: toDate ? `${toDate}T23:59:59.999Z` : undefined,
  };
  
  const { data: usageReport, isLoading } = useGetUsage(queryParams, {
    query: {
      queryKey: getGetUsageQueryKey(queryParams)
    }
  });

  // Group events by day for the chart
  const chartData = useMemo(() => {
    if (!usageReport?.events) return [];
    
    const grouped = usageReport.events.reduce((acc, event) => {
      if (!event.createdAt) return acc;
      
      const date = new Date(event.createdAt).toLocaleDateString("en-US", { month: "short", day: "numeric" });
      if (!acc[date]) {
        acc[date] = { date, callMinutes: 0, registrations: 0, callsPlaced: 0 };
      }
      
      acc[date].callMinutes += event.callMinutes;
      acc[date].registrations += event.registrations;
      acc[date].callsPlaced += event.callsPlaced;
      
      return acc;
    }, {} as Record<string, { date: string, callMinutes: number, registrations: number, callsPlaced: number }>);
    
    return Object.values(grouped)
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
  }, [usageReport?.events]);

  return (
    <div className="space-y-8">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Usage Report</h1>
          <p className="text-muted-foreground mt-2">Monitor SDK consumption across the platform.</p>
        </div>
      </div>

      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-4">
        <div className="w-full sm:w-64">
          <label className="text-sm font-medium text-muted-foreground mb-1 block">Provider</label>
          <Select value={providerId} onValueChange={setProviderId} >
            <SelectTrigger data-testid="select-provider">
              <SelectValue placeholder="All Providers" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Providers</SelectItem>
              {providers?.map(p => (
                <SelectItem key={p.id} value={p.id} data-testid={`select-provider-${p.id}`}>{p.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="flex gap-3 flex-1 items-end">
          <div className="flex-1">
            <label className="text-sm font-medium text-muted-foreground mb-1 block" htmlFor="from-date">From</label>
            <input
              id="from-date"
              type="date"
              value={fromDate}
              onChange={(e) => setFromDate(e.target.value)}
              data-testid="input-from-date"
              className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50 text-foreground"
            />
          </div>
          <div className="flex-1">
            <label className="text-sm font-medium text-muted-foreground mb-1 block" htmlFor="to-date">To</label>
            <input
              id="to-date"
              type="date"
              value={toDate}
              onChange={(e) => setToDate(e.target.value)}
              data-testid="input-to-date"
              className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50 text-foreground"
            />
          </div>
        </div>
      </div>

      {isLoading ? (
        <div className="animate-pulse space-y-8">
          <div className="grid grid-cols-3 gap-4">
            <div className="h-32 bg-muted rounded-xl"></div>
            <div className="h-32 bg-muted rounded-xl"></div>
            <div className="h-32 bg-muted rounded-xl"></div>
          </div>
          <div className="h-80 bg-muted rounded-xl"></div>
        </div>
      ) : usageReport ? (
        <>
          <div className="grid gap-4 md:grid-cols-3">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Total Call Minutes</CardTitle>
                <Activity className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold text-primary" data-testid="usage-call-minutes">
                  {usageReport.total.callMinutes.toLocaleString()}
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Total Registrations</CardTitle>
                <Server className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold" data-testid="usage-registrations">
                  {usageReport.total.registrations.toLocaleString()}
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Calls Placed</CardTitle>
                <PhoneCall className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold" data-testid="usage-calls-placed">
                  {usageReport.total.callsPlaced.toLocaleString()}
                </div>
              </CardContent>
            </Card>
          </div>

          <Card className="pt-6">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">Call Minutes &amp; Registrations by Day</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="h-[350px] w-full">
                {chartData.length > 0 ? (
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={chartData} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                      <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border)" opacity={0.5} />
                      <XAxis 
                        dataKey="date" 
                        axisLine={false}
                        tickLine={false}
                        tick={{ fontSize: 12, fill: "var(--muted-foreground)" }}
                        dy={10}
                      />
                      <YAxis 
                        yAxisId="left"
                        axisLine={false}
                        tickLine={false}
                        tick={{ fontSize: 12, fill: "var(--muted-foreground)" }}
                      />
                      <YAxis 
                        yAxisId="right" 
                        orientation="right"
                        axisLine={false}
                        tickLine={false}
                        tick={{ fontSize: 12, fill: "var(--muted-foreground)" }}
                      />
                      <Tooltip 
                        contentStyle={{ 
                          backgroundColor: "hsl(var(--card))", 
                          borderColor: "hsl(var(--border))",
                          borderRadius: "var(--radius)",
                          fontSize: "12px",
                          boxShadow: "var(--shadow-md)"
                        }}
                      />
                      <Legend wrapperStyle={{ fontSize: "12px", paddingTop: "10px" }} />
                      <Bar yAxisId="left" dataKey="callMinutes" name="Call Minutes" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
                      <Bar yAxisId="right" dataKey="registrations" name="Registrations" fill="hsl(var(--muted-foreground))" radius={[4, 4, 0, 0]} opacity={0.4} />
                    </BarChart>
                  </ResponsiveContainer>
                ) : (
                  <div className="h-full flex items-center justify-center text-muted-foreground">
                    No usage data available for this period
                  </div>
                )}
              </div>
            </CardContent>
          </Card>

          <div className="border rounded-md bg-card">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>License ID</TableHead>
                  <TableHead>Device ID</TableHead>
                  <TableHead className="text-right">Call Minutes</TableHead>
                  <TableHead className="text-right">Registrations</TableHead>
                  <TableHead className="text-right">Calls Placed</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {usageReport.events.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={6} className="text-center py-8 text-muted-foreground">No events in this date range.</TableCell>
                  </TableRow>
                ) : (
                  usageReport.events.map((event) => (
                    <TableRow key={event.id} data-testid={`row-event-${event.id}`}>
                      <TableCell className="whitespace-nowrap">
                        {event.createdAt ? new Date(event.createdAt).toLocaleString() : 'N/A'}
                      </TableCell>
                      <TableCell className="font-mono text-xs text-muted-foreground">{event.licenseId.split('-')[0]}</TableCell>
                      <TableCell className="font-mono text-xs text-muted-foreground truncate max-w-[120px]">{event.deviceId}</TableCell>
                      <TableCell className="text-right font-medium">{event.callMinutes}</TableCell>
                      <TableCell className="text-right">{event.registrations}</TableCell>
                      <TableCell className="text-right">{event.callsPlaced}</TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>
        </>
      ) : null}
    </div>
  );
}
