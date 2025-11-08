#!/usr/bin/env python3
"""
Analisi e Visualizzazione Risultati Benchmark
Genera grafici e tabelle comparative dai risultati CSV
"""

import csv
import sys
import os
from pathlib import Path
from collections import defaultdict
import argparse


def load_csv_results(csv_file):
    """Carica risultati da file CSV"""
    results = defaultdict(lambda: defaultdict(dict))

    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            config = row['Config']
            test = row['Test']
            results[config][test] = row

    return results


def print_summary_table(results):
    """Stampa tabella riassuntiva"""
    print("\n" + "="*80)
    print("RIEPILOGO BENCHMARK")
    print("="*80 + "\n")

    configs = sorted(results.keys())

    # Build Time
    print("\n📦 BUILD TIME & SIZE")
    print("-" * 80)
    print(f"{'Config':<15} {'Initial (s)':<15} {'Rebuild (s)':<15} {'Size (MB)':<15}")
    print("-" * 80)

    for config in configs:
        build_time = results[config].get('Build', {}).get('BuildTime_s', '-')
        rebuild_time = results[config].get('Rebuild', {}).get('BuildTime_s', '-')
        size = results[config].get('Build', {}).get('ImageSize_MB', '-')

        print(f"{config:<15} {build_time:<15} {rebuild_time:<15} {size:<15}")

    # Build Energy
    print("\n⚡ BUILD ENERGY")
    print("-" * 80)
    print(f"{'Config':<15} {'Initial (J)':<15} {'Rebuild (J)':<15}")
    print("-" * 80)

    for config in configs:
        build_energy = results[config].get('Build', {}).get('BuildEnergy_J', '-')
        rebuild_energy = results[config].get('Rebuild', {}).get('BuildEnergy_J', '-')

        print(f"{config:<15} {build_energy:<15} {rebuild_energy:<15}")

    # Startup
    print("\n🚀 STARTUP")
    print("-" * 80)
    print(f"{'Config':<15} {'Time (s)':<15} {'Energy (J)':<15}")
    print("-" * 80)

    for config in configs:
        startup_time = results[config].get('Startup', {}).get('StartupTime_s', '-')
        startup_energy = results[config].get('Startup', {}).get('StartupEnergy_J', '-')

        print(f"{config:<15} {startup_time:<15} {startup_energy:<15}")

    # Idle
    print("\n💤 IDLE (30s)")
    print("-" * 80)
    print(f"{'Config':<15} {'Energy (J)':<15} {'CPU %':<15} {'RAM (MB)':<15}")
    print("-" * 80)

    for config in configs:
        idle_energy = results[config].get('Idle', {}).get('IdleEnergy_J', '-')
        cpu_avg = results[config].get('Idle', {}).get('CPUAvg_%', '-')
        mem_avg = results[config].get('Idle', {}).get('MemoryAvg_MB', '-')

        print(f"{config:<15} {idle_energy:<15} {cpu_avg:<15} {mem_avg:<15}")

    # Load Test
    print("\n🔥 LOAD TEST (60s)")
    print("-" * 80)
    print(f"{'Config':<15} {'Energy (J)':<15} {'CPU Avg %':<15} {'RAM Avg (MB)':<15} {'RAM Peak (MB)':<15}")
    print("-" * 80)

    for config in configs:
        load_energy = results[config].get('Load', {}).get('LoadAvgEnergy_J', '-')
        cpu_avg = results[config].get('Load', {}).get('CPUAvg_%', '-')
        mem_avg = results[config].get('Load', {}).get('MemoryAvg_MB', '-')
        mem_peak = results[config].get('Load', {}).get('MemoryPeak_MB', '-')

        print(f"{config:<15} {load_energy:<15} {cpu_avg:<15} {mem_avg:<15} {mem_peak:<15}")

    print("\n" + "="*80 + "\n")


def calculate_comparisons(results):
    """Calcola confronti percentuali rispetto a baseline (fatjar)"""
    baseline = 'fatjar'

    if baseline not in results:
        print(f"Baseline '{baseline}' non trovata nei risultati")
        return

    print("\n" + "="*80)
    print("CONFRONTO vs BASELINE (Fat JAR)")
    print("="*80 + "\n")

    metrics = [
        ('Build', 'BuildTime_s', 'Initial Build Time'),
        ('Rebuild', 'BuildTime_s', 'Rebuild Time'),
        ('Build', 'ImageSize_MB', 'Image Size'),
        ('Build', 'BuildEnergy_J', 'Initial Build Energy'),
        ('Startup', 'StartupTime_s', 'Startup Time'),
        ('Startup', 'StartupEnergy_J', 'Startup Energy'),
        ('Idle', 'IdleEnergy_J', 'Idle Energy'),
        ('Idle', 'MemoryAvg_MB', 'Idle Memory'),
        ('Load', 'LoadAvgEnergy_J', 'Load Energy'),
        ('Load', 'MemoryAvg_MB', 'Load Memory'),
    ]

    for test, metric, label in metrics:
        print(f"\n📊 {label}:")
        print("-" * 60)

        baseline_val = results[baseline].get(test, {}).get(metric, None)

        if not baseline_val or baseline_val == '-':
            print(f"  Dati baseline non disponibili")
            continue

        try:
            baseline_val = float(baseline_val)
        except ValueError:
            print(f"  Valore baseline non valido: {baseline_val}")
            continue

        print(f"  {'Baseline (fatjar):':<25} {baseline_val:.2f}")

        for config in sorted(results.keys()):
            if config == baseline:
                continue

            val = results[config].get(test, {}).get(metric, None)

            if not val or val == '-':
                print(f"  {config:<25} N/A")
                continue

            try:
                val = float(val)
                diff_pct = ((val - baseline_val) / baseline_val) * 100

                if diff_pct < 0:
                    symbol = "🟢"
                    sign = ""
                elif diff_pct > 0:
                    symbol = "🔴"
                    sign = "+"
                else:
                    symbol = "⚪"
                    sign = ""

                print(f"  {config:<25} {val:.2f} ({symbol} {sign}{diff_pct:.1f}%)")

            except ValueError:
                print(f"  {config:<25} Valore non valido: {val}")

    print("\n" + "="*80 + "\n")


def generate_markdown_report(results, output_file):
    """Genera report in formato Markdown"""
    with open(output_file, 'w') as f:
        f.write("# Benchmark Results Report\n\n")
        f.write(f"Generated: {os.popen('date').read()}\n\n")

        # Build Table
        f.write("## Build Performance\n\n")
        f.write("| Config | Initial Build (s) | Rebuild (s) | Size (MB) | Initial Energy (J) | Rebuild Energy (J) |\n")
        f.write("|--------|-------------------|-------------|-----------|--------------------|--------------------|  \n")

        for config in sorted(results.keys()):
            build_time = results[config].get('Build', {}).get('BuildTime_s', '-')
            rebuild_time = results[config].get('Rebuild', {}).get('BuildTime_s', '-')
            size = results[config].get('Build', {}).get('ImageSize_MB', '-')
            build_energy = results[config].get('Build', {}).get('BuildEnergy_J', '-')
            rebuild_energy = results[config].get('Rebuild', {}).get('BuildEnergy_J', '-')

            f.write(f"| {config} | {build_time} | {rebuild_time} | {size} | {build_energy} | {rebuild_energy} |\n")

        # Startup Table
        f.write("\n## Startup Performance\n\n")
        f.write("| Config | Time (s) | Energy (J) |\n")
        f.write("|--------|----------|------------|\n")

        for config in sorted(results.keys()):
            startup_time = results[config].get('Startup', {}).get('StartupTime_s', '-')
            startup_energy = results[config].get('Startup', {}).get('StartupEnergy_J', '-')

            f.write(f"| {config} | {startup_time} | {startup_energy} |\n")

        # Idle Table
        f.write("\n## Idle Performance\n\n")
        f.write("| Config | Energy (J) | CPU (%) | Memory (MB) |\n")
        f.write("|--------|------------|---------|-------------|\n")

        for config in sorted(results.keys()):
            idle_energy = results[config].get('Idle', {}).get('IdleEnergy_J', '-')
            cpu_avg = results[config].get('Idle', {}).get('CPUAvg_%', '-')
            mem_avg = results[config].get('Idle', {}).get('MemoryAvg_MB', '-')

            f.write(f"| {config} | {idle_energy} | {cpu_avg} | {mem_avg} |\n")

        # Load Table
        f.write("\n## Load Test Performance\n\n")
        f.write("| Config | Energy (J) | CPU Avg (%) | Memory Avg (MB) | Memory Peak (MB) |\n")
        f.write("|--------|------------|-------------|-----------------|------------------|\n")

        for config in sorted(results.keys()):
            load_energy = results[config].get('Load', {}).get('LoadAvgEnergy_J', '-')
            cpu_avg = results[config].get('Load', {}).get('CPUAvg_%', '-')
            mem_avg = results[config].get('Load', {}).get('MemoryAvg_MB', '-')
            mem_peak = results[config].get('Load', {}).get('MemoryPeak_MB', '-')

            f.write(f"| {config} | {load_energy} | {cpu_avg} | {mem_avg} | {mem_peak} |\n")

    print(f"✅ Report Markdown generato: {output_file}")


def main():
    parser = argparse.ArgumentParser(description='Analizza risultati benchmark')
    parser.add_argument('csv_file', help='File CSV con i risultati')
    parser.add_argument('--markdown', '-m', help='Genera report Markdown', metavar='OUTPUT')

    args = parser.parse_args()

    if not os.path.exists(args.csv_file):
        print(f"❌ File non trovato: {args.csv_file}")
        sys.exit(1)

    # Carica risultati
    results = load_csv_results(args.csv_file)

    if not results:
        print("❌ Nessun risultato trovato nel CSV")
        sys.exit(1)

    # Stampa tabelle
    print_summary_table(results)
    calculate_comparisons(results)

    # Genera Markdown se richiesto
    if args.markdown:
        generate_markdown_report(results, args.markdown)


if __name__ == '__main__':
    main()

