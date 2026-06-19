import { useState } from "react";
import { useLocation } from "wouter";
import { getAdminSummary } from "@workspace/api-client-react";
import { Shield } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";

export default function Login() {
  const [, setLocation] = useLocation();
  const [apiKey, setApiKey] = useState("");
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!apiKey) return;

    setIsLoading(true);
    setError("");

    try {
      // Test the API key by trying to fetch the summary
      await getAdminSummary({
        headers: {
          Authorization: `Bearer ${apiKey}`
        }
      });
      
      // If successful, save to localStorage
      localStorage.setItem("adminApiKey", apiKey);
      setLocation("/");
    } catch (err: any) {
      if (err?.status === 401) {
        setError("Invalid API key");
      } else {
        setError("Connection failed. Please try again.");
      }
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen w-full flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md border-border bg-card shadow-2xl">
        <CardHeader className="space-y-1 text-center pb-8 pt-10">
          <div className="mx-auto w-12 h-12 bg-primary/10 rounded-full flex items-center justify-center mb-4">
            <Shield className="w-6 h-6 text-primary" />
          </div>
          <CardTitle className="text-2xl font-bold tracking-tight">SipKit Ops</CardTitle>
          <CardDescription className="text-muted-foreground">
            Enter your operator API key to access the console
          </CardDescription>
        </CardHeader>
        <form onSubmit={handleSubmit}>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="apiKey">Admin API Key</Label>
              <Input
                id="apiKey"
                type="password"
                placeholder="sk_admin_..."
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                autoComplete="off"
                data-testid="input-apikey"
                className="font-mono"
              />
            </div>
            {error && (
              <div className="text-sm font-medium text-destructive" data-testid="error-message">
                {error}
              </div>
            )}
          </CardContent>
          <CardFooter className="pb-10">
            <Button 
              type="submit" 
              className="w-full" 
              disabled={isLoading || !apiKey}
              data-testid="button-login"
            >
              {isLoading ? "Authenticating..." : "Access Console"}
            </Button>
          </CardFooter>
        </form>
      </Card>
    </div>
  );
}
