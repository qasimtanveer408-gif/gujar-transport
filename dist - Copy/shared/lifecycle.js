export const lifecycleResources = {
    vehicles: 'Vehicles', drivers: 'Drivers', trips: 'Trips', maintenance: 'Maintenance & oil',
    companies: 'Fleet companies', 'office-expenses': 'Office expenses', bookings: 'Bookings',
    periods: 'Accounting periods', loans: 'Driver loans', 'loan-transactions': 'Loan transactions',
    earnings: 'Driver earnings', payments: 'Driver payments', cash: 'Cash transactions',
    routes: 'Routes', 'custom-fields': 'Custom fields', documents: 'Documents',
    assignments: 'Vehicle assignments', duty: 'Duty sessions', imports: 'Import batches',
    notifications: 'Notifications', users: 'Users', roles: 'Roles',
};
export const hasLifecycleAccess = (permissions) => permissions.some(p => p === 'records.archive' || p === 'records.delete');
