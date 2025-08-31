#!/usr/bin/env python
from lxml import etree
import fnmatch
import subprocess

EXCLUSIONS = "exclude-chapters.txt"
DATASTREAM = "content/build/ssg-almalinux9-ds.xml"
TREE = etree.parse(DATASTREAM)
NAMESPACE = {'NS': 'http://checklists.nist.gov/xccdf/1.2'}


def get_rule_idrefs():
    """
    Extract rule idrefs from the specified profile.
    """
    expr = '//NS:Profile[@id="xccdf_org.ssgproject.content_profile_cis_server_l1"]//NS:select'
    idrefs = []
    for sel in TREE.xpath(expr, namespaces=NAMESPACE):
        idref = sel.get('idref')
        if idref:
            idrefs.append(idref)
    return idrefs


def check_rules_for_cis_reference(idrefs):
    """
    Check each rule for references to CIS benchmarks
    and return a mapping of rule idrefs to CIS references.
    """
    mapping = {}
    for idref in idrefs:
        rule_xpath = f'//NS:Rule[@id="{idref}"]'
        rule = TREE.xpath(rule_xpath, namespaces=NAMESPACE)
        if not rule:
            continue
        rule = rule[0]
        references = rule.xpath('.//NS:reference[contains(@href, "cisecurity.org/benchmark/")]', namespaces=NAMESPACE)
        if references:
            mapping[idref] = [ref.text for ref in references if ref.text]
    return mapping


def filter_mapping(mapping):
    """
    Filter out mapping entries based on exclusions.
    """
    with open(EXCLUSIONS) as f:
        exclusions = [line.strip() for line in f if line.strip() and not line.startswith('#')]

    # Remove mapping entries where any CIS reference matches an exclusion (supports wildcards)
    to_remove = []
    for rule_id, refs in mapping.items():
        for ref in refs:
            for exclusion in exclusions:
                if fnmatch.fnmatch(ref, exclusion):
                    to_remove.append(rule_id)
                    break
            else:
                continue
            break
    for rule_id in to_remove:
        del mapping[rule_id]
    return mapping


def strip_mapping_to_ids(mapping):
    """
    Strip the mapping to just rule IDs without the prefix.
    """
    return [key.replace("xccdf_org.ssgproject.content_rule_", "") for key in mapping.keys()]


if __name__ == "__main__":
    idrefs = get_rule_idrefs()
    mapping = check_rules_for_cis_reference(idrefs)
    filtered_mapping = filter_mapping(mapping)
    final_ids = strip_mapping_to_ids(filtered_mapping)

    cmd = ["autotailor", "-o", "custom-tailoring.xml", "-p", "custom", DATASTREAM, "cis_server_l1"]
    for rule_id in final_ids:
        cmd.extend(["-u", rule_id])
    subprocess.run(cmd, check=True)
