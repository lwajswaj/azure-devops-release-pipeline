using System;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;

namespace Application.Models
{
    public partial class AgendaContext : DbContext
    {
        public AgendaContext()
        {
        }

        public AgendaContext(DbContextOptions<AgendaContext> options)
            : base(options)
        {
        }

        public virtual DbSet<Contacts> Contacts { get; set; }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {

        }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Contacts>(entity =>
            {
                entity.Property(e => e.Email)
                    .HasMaxLength(50)
                    .IsUnicode(false);

                entity.Property(e => e.LastName)
                    .IsRequired()
                    .HasMaxLength(50);

                entity.Property(e => e.Name)
                    .IsRequired()
                    .HasMaxLength(50);

                entity.Property(e => e.Phone)
                    .HasMaxLength(15)
                    .IsUnicode(false);
            });
        }
    }
}
