import { useState } from "react";
import { Link } from "wouter";
import { useListProviders, useCreateProvider, useDeleteProvider, getListProvidersQueryKey } from "@workspace/api-client-react";
import { useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog";
import { Trash2, Plus, ArrowRight } from "lucide-react";
import { useToast } from "@/hooks/use-toast";

export default function Providers() {
  const { data: providers, isLoading } = useListProviders();
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [name, setName] = useState("");
  const [contactEmail, setContactEmail] = useState("");
  
  const queryClient = useQueryClient();
  const { toast } = useToast();

  const createProvider = useCreateProvider();
  const deleteProvider = useDeleteProvider();

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    createProvider.mutate(
      { data: { name, contactEmail } },
      {
        onSuccess: () => {
          setIsCreateOpen(false);
          setName("");
          setContactEmail("");
          queryClient.invalidateQueries({ queryKey: getListProvidersQueryKey() });
          toast({ title: "Provider created successfully" });
        },
        onError: () => {
          toast({ variant: "destructive", title: "Failed to create provider" });
        }
      }
    );
  };

  const handleDelete = async (providerId: string) => {
    deleteProvider.mutate(
      { providerId },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: getListProvidersQueryKey() });
          toast({ title: "Provider deleted" });
        },
        onError: () => {
          toast({ variant: "destructive", title: "Failed to delete provider" });
        }
      }
    );
  };

  return (
    <div className="space-y-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Providers</h1>
          <p className="text-muted-foreground mt-2">Manage SDK providers and clients.</p>
        </div>

        <Dialog open={isCreateOpen} onOpenChange={setIsCreateOpen}>
          <DialogTrigger asChild>
            <Button data-testid="button-create-provider">
              <Plus className="w-4 h-4 mr-2" />
              New Provider
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Create Provider</DialogTitle>
              <DialogDescription>Add a new SDK provider to the platform.</DialogDescription>
            </DialogHeader>
            <form onSubmit={handleCreate} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="name">Company Name</Label>
                <Input
                  id="name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  required
                  data-testid="input-provider-name"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="email">Contact Email</Label>
                <Input
                  id="email"
                  type="email"
                  value={contactEmail}
                  onChange={(e) => setContactEmail(e.target.value)}
                  required
                  data-testid="input-provider-email"
                />
              </div>
              <DialogFooter>
                <Button type="submit" disabled={createProvider.isPending} data-testid="button-submit-provider">
                  {createProvider.isPending ? "Creating..." : "Create Provider"}
                </Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>
      </div>

      <div className="border rounded-md bg-card">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>ID</TableHead>
              <TableHead>Name</TableHead>
              <TableHead>Contact Email</TableHead>
              <TableHead>Created At</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoading ? (
              <TableRow>
                <TableCell colSpan={5} className="text-center py-8 text-muted-foreground">Loading...</TableCell>
              </TableRow>
            ) : providers?.length === 0 ? (
              <TableRow>
                <TableCell colSpan={5} className="text-center py-8 text-muted-foreground">No providers found.</TableCell>
              </TableRow>
            ) : (
              providers?.map((provider) => (
                <TableRow key={provider.id}>
                  <TableCell className="font-mono text-xs text-muted-foreground">{provider.id.split('-')[0]}</TableCell>
                  <TableCell className="font-medium" data-testid={`text-provider-name-${provider.id}`}>{provider.name}</TableCell>
                  <TableCell>{provider.contactEmail}</TableCell>
                  <TableCell className="text-muted-foreground text-sm">
                    {provider.createdAt ? new Date(provider.createdAt).toLocaleDateString() : 'N/A'}
                  </TableCell>
                  <TableCell className="text-right space-x-2">
                    <Link href={`/providers/${provider.id}`}>
                      <Button variant="ghost" size="sm" data-testid={`link-provider-${provider.id}`}>
                        Manage
                        <ArrowRight className="w-4 h-4 ml-2" />
                      </Button>
                    </Link>
                    <AlertDialog>
                      <AlertDialogTrigger asChild>
                        <Button variant="ghost" size="icon" className="text-destructive hover:bg-destructive/10 hover:text-destructive" data-testid={`button-delete-provider-${provider.id}`}>
                          <Trash2 className="w-4 h-4" />
                        </Button>
                      </AlertDialogTrigger>
                      <AlertDialogContent>
                        <AlertDialogHeader>
                          <AlertDialogTitle>Delete Provider?</AlertDialogTitle>
                          <AlertDialogDescription>
                            This will permanently delete the provider "{provider.name}" and all associated licenses. This action cannot be undone.
                          </AlertDialogDescription>
                        </AlertDialogHeader>
                        <AlertDialogFooter>
                          <AlertDialogCancel>Cancel</AlertDialogCancel>
                          <AlertDialogAction 
                            onClick={() => handleDelete(provider.id)}
                            className="bg-destructive hover:bg-destructive/90"
                            data-testid="button-confirm-delete"
                          >
                            Delete
                          </AlertDialogAction>
                        </AlertDialogFooter>
                      </AlertDialogContent>
                    </AlertDialog>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
