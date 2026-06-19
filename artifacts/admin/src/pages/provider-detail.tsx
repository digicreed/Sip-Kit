import { useState } from "react";
import { useParams, Link } from "wouter";
import { 
  useListProviders, 
  useListLicenses, 
  useIssueLicense, 
  useRevokeLicense, 
  getListLicensesQueryKey,
  type LicenseIssued
} from "@workspace/api-client-react";
import { useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { ArrowLeft, KeyRound, Ban, Copy, Check } from "lucide-react";
import { useToast } from "@/hooks/use-toast";

const AVAILABLE_FEATURES = ["audio", "video", "conference", "transfer", "dtmf"];

export default function ProviderDetail() {
  const params = useParams();
  const providerId = params.providerId!;
  
  const { data: providers, isLoading: loadingProviders } = useListProviders();
  const provider = providers?.find(p => p.id === providerId);

  const { data: licenses, isLoading: loadingLicenses } = useListLicenses(providerId, {
    query: {
      enabled: !!providerId,
      queryKey: getListLicensesQueryKey(providerId)
    }
  });

  const [isIssueOpen, setIsIssueOpen] = useState(false);
  const [isIssuedModalOpen, setIsIssuedModalOpen] = useState(false);
  const [issuedLicense, setIssuedLicense] = useState<LicenseIssued | null>(null);
  const [copied, setCopied] = useState(false);

  // Form State
  const [features, setFeatures] = useState<string[]>(["audio"]);
  const [maxAccounts, setMaxAccounts] = useState(100);
  const [maxConcurrentCalls, setMaxConcurrentCalls] = useState(10);
  const [maxDevices, setMaxDevices] = useState(200);
  const [expiresAt, setExpiresAt] = useState("");

  const queryClient = useQueryClient();
  const { toast } = useToast();

  const issueLicense = useIssueLicense();
  const revokeLicense = useRevokeLicense();

  const handleIssue = async (e: React.FormEvent) => {
    e.preventDefault();
    
    issueLicense.mutate(
      { 
        providerId, 
        data: { 
          features, 
          maxAccounts, 
          maxConcurrentCalls, 
          maxDevices, 
          expiresAt: expiresAt || null 
        } 
      },
      {
        onSuccess: (data) => {
          setIsIssueOpen(false);
          setIssuedLicense(data);
          setIsIssuedModalOpen(true);
          
          // Reset form
          setFeatures(["audio"]);
          setMaxAccounts(100);
          setMaxConcurrentCalls(10);
          setMaxDevices(200);
          setExpiresAt("");
          
          queryClient.invalidateQueries({ queryKey: getListLicensesQueryKey(providerId) });
        },
        onError: () => {
          toast({ variant: "destructive", title: "Failed to issue license" });
        }
      }
    );
  };

  const handleRevoke = async (licenseId: string) => {
    revokeLicense.mutate(
      { licenseId },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: getListLicensesQueryKey(providerId) });
          toast({ title: "License revoked" });
        },
        onError: () => {
          toast({ variant: "destructive", title: "Failed to revoke license" });
        }
      }
    );
  };

  const copyToClipboard = () => {
    if (issuedLicense?.licenseKey) {
      navigator.clipboard.writeText(issuedLicense.licenseKey);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const toggleFeature = (feature: string) => {
    setFeatures(prev => 
      prev.includes(feature) 
        ? prev.filter(f => f !== feature)
        : [...prev, feature]
    );
  };

  if (loadingProviders || loadingLicenses) {
    return <div className="animate-pulse space-y-8">
      <div className="h-8 w-32 bg-muted rounded"></div>
      <div className="h-32 bg-muted rounded-xl"></div>
    </div>;
  }

  if (!provider) {
    return <div className="text-destructive">Provider not found.</div>;
  }

  return (
    <div className="space-y-8">
      <div>
        <Link href="/providers" className="inline-flex items-center text-sm text-muted-foreground hover:text-foreground mb-4 transition-colors">
          <ArrowLeft className="w-4 h-4 mr-2" />
          Back to Providers
        </Link>
        <h1 className="text-3xl font-bold tracking-tight">{provider.name}</h1>
        <p className="text-muted-foreground mt-2">ID: <span className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">{provider.id}</span> • {provider.contactEmail}</p>
      </div>

      <div className="flex items-center justify-between border-t border-border pt-8">
        <div>
          <h2 className="text-xl font-semibold">Licenses</h2>
          <p className="text-sm text-muted-foreground mt-1">Manage SDK licenses for this provider.</p>
        </div>

        <Dialog open={isIssueOpen} onOpenChange={setIsIssueOpen}>
          <DialogTrigger asChild>
            <Button data-testid="button-issue-license">
              <KeyRound className="w-4 h-4 mr-2" />
              Issue License
            </Button>
          </DialogTrigger>
          <DialogContent className="max-w-xl">
            <DialogHeader>
              <DialogTitle>Issue New License</DialogTitle>
              <DialogDescription>Configure constraints and capabilities for the new license key.</DialogDescription>
            </DialogHeader>
            <form onSubmit={handleIssue} className="space-y-6">
              
              <div className="space-y-3">
                <Label>Features</Label>
                <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
                  {AVAILABLE_FEATURES.map(feature => (
                    <div key={feature} className="flex items-center space-x-2 bg-muted/50 p-2 rounded border border-border/50">
                      <Checkbox 
                        id={`feat-${feature}`} 
                        checked={features.includes(feature)}
                        onCheckedChange={() => toggleFeature(feature)}
                      />
                      <label htmlFor={`feat-${feature}`} className="text-sm font-medium capitalize cursor-pointer">
                        {feature}
                      </label>
                    </div>
                  ))}
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="maxAccounts">Max Accounts</Label>
                  <Input 
                    id="maxAccounts" 
                    type="number" 
                    min="1"
                    value={maxAccounts}
                    onChange={(e) => setMaxAccounts(parseInt(e.target.value))}
                    required
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="maxConcurrentCalls">Concurrent Calls</Label>
                  <Input 
                    id="maxConcurrentCalls" 
                    type="number" 
                    min="1"
                    value={maxConcurrentCalls}
                    onChange={(e) => setMaxConcurrentCalls(parseInt(e.target.value))}
                    required
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="maxDevices">Max Devices</Label>
                  <Input 
                    id="maxDevices" 
                    type="number" 
                    min="1"
                    value={maxDevices}
                    onChange={(e) => setMaxDevices(parseInt(e.target.value))}
                    required
                  />
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="expiresAt">Expiration Date (Optional)</Label>
                <Input 
                  id="expiresAt" 
                  type="date"
                  value={expiresAt}
                  onChange={(e) => setExpiresAt(e.target.value)}
                />
              </div>

              <DialogFooter>
                <Button type="submit" disabled={issueLicense.isPending} data-testid="button-submit-license">
                  {issueLicense.isPending ? "Issuing..." : "Issue License"}
                </Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>
      </div>

      {/* Issued License Modal */}
      <Dialog open={isIssuedModalOpen} onOpenChange={(open) => {
        if (!open) {
          setIsIssuedModalOpen(false);
          setIssuedLicense(null);
        }
      }}>
        <DialogContent className="sm:max-w-md border-primary/20">
          <DialogHeader>
            <DialogTitle className="text-xl">License Issued Successfully</DialogTitle>
            <DialogDescription className="text-destructive font-medium mt-2">
              Warning: This is the only time the full license key will be displayed. Please copy it now.
            </DialogDescription>
          </DialogHeader>
          
          <div className="my-6 space-y-4">
            <div className="space-y-2">
              <Label>License Key</Label>
              <div className="flex relative">
                <Input 
                  readOnly 
                  value={issuedLicense?.licenseKey || ""} 
                  className="font-mono text-sm bg-muted pr-12"
                  data-testid="input-issued-key"
                />
                <Button 
                  size="icon" 
                  variant="ghost" 
                  className="absolute right-1 top-1 h-7 w-7 text-muted-foreground hover:text-foreground"
                  onClick={copyToClipboard}
                >
                  {copied ? <Check className="h-4 w-4 text-green-500" /> : <Copy className="h-4 w-4" />}
                </Button>
              </div>
            </div>
          </div>

          <DialogFooter>
            <Button onClick={() => setIsIssuedModalOpen(false)}>I have copied the key</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <div className="border rounded-md bg-card">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Key Prefix</TableHead>
              <TableHead>Constraints</TableHead>
              <TableHead>Features</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {licenses?.length === 0 ? (
              <TableRow>
                <TableCell colSpan={5} className="text-center py-8 text-muted-foreground">No licenses issued yet.</TableCell>
              </TableRow>
            ) : (
              licenses?.map((license) => {
                const isRevoked = !!license.revokedAt;
                
                return (
                  <TableRow key={license.id} className={isRevoked ? "opacity-60 bg-muted/30" : ""}>
                    <TableCell>
                      <div className="font-mono text-sm font-medium">{license.keyPrefix}****</div>
                      <div className="text-xs text-muted-foreground mt-1">ID: {license.id.split('-')[0]}</div>
                    </TableCell>
                    <TableCell>
                      <div className="text-xs space-y-1">
                        <div><span className="text-muted-foreground">Accounts:</span> {license.maxAccounts}</div>
                        <div><span className="text-muted-foreground">Calls:</span> {license.maxConcurrentCalls}</div>
                        <div><span className="text-muted-foreground">Devices:</span> {license.maxDevices}</div>
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1 max-w-[200px]">
                        {license.features.map(f => (
                          <Badge key={f} variant="secondary" className="text-[10px] py-0">{f}</Badge>
                        ))}
                      </div>
                    </TableCell>
                    <TableCell>
                      {isRevoked ? (
                        <Badge variant="destructive" className="bg-destructive/10 text-destructive border-transparent">Revoked</Badge>
                      ) : (
                        <div className="space-y-1">
                          <Badge variant="outline" className="bg-green-500/10 text-green-600 border-green-500/20">Active</Badge>
                          {license.expiresAt && (
                            <div className="text-xs text-muted-foreground">Exp: {new Date(license.expiresAt).toLocaleDateString()}</div>
                          )}
                        </div>
                      )}
                    </TableCell>
                    <TableCell className="text-right">
                      {!isRevoked && (
                        <AlertDialog>
                          <AlertDialogTrigger asChild>
                            <Button variant="ghost" size="sm" className="text-destructive hover:bg-destructive/10 hover:text-destructive" data-testid={`button-revoke-${license.id}`}>
                              <Ban className="w-4 h-4 mr-2" />
                              Revoke
                            </Button>
                          </AlertDialogTrigger>
                          <AlertDialogContent>
                            <AlertDialogHeader>
                              <AlertDialogTitle>Revoke License?</AlertDialogTitle>
                              <AlertDialogDescription>
                                This will permanently revoke the license starting with <span className="font-mono">{license.keyPrefix}</span>. Active SDK clients using this key will be rejected on their next token refresh.
                              </AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                              <AlertDialogCancel>Cancel</AlertDialogCancel>
                              <AlertDialogAction 
                                onClick={() => handleRevoke(license.id)}
                                className="bg-destructive hover:bg-destructive/90"
                                data-testid="button-confirm-revoke"
                              >
                                Revoke License
                              </AlertDialogAction>
                            </AlertDialogFooter>
                          </AlertDialogContent>
                        </AlertDialog>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
