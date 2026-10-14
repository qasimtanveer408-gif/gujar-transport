export const lifecycleResources = {
  vehicles: 'Vehicles', drivers: 'Drivers', trips: 'Trips', maintenance: 'Maintenance & oil',
  companies: 'Fleet companies', 'office-expenses': 'Office expenses', bookings: 'Bookings',
  periods: 'Accounting periods', loans: 'Driver loans', 'loan-transactions': 'Loan transactions',
  earnings: 'Driver earnings', payments: 'Driver payments', cash: 'Cash transactions',
  routes: 'Routes', 'custom-fields': 'Custom fields', documents: 'Documents',
  assignments: 'Vehicle assignments', duty: 'Duty sessions', imports: 'Import batches',
  notifications: 'Notifications', users: 'Users', roles: 'Roles',
} as const;
export type LifecycleResource = keyof typeof lifecycleResources;
export type LifecycleAction = 'archive' | 'restore' | 'delete';
export type LifecyclePreview = {
  resource: string; id: string; label: string; version: number; archived_at: string | null;
  token: string; counts: {table: string; count: number}[]; total: number;
  closed_periods: string[]; cross_period: boolean; protected: boolean;
};
export const hasLifecycleAccess = (permissions: string[]) =>
  permissions.some(p => p === 'records.archive' || p === 'records.delete');
