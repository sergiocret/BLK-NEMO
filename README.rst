.. todo::
.. contents::
   :local:





Welcome to NEMO home page!
==========================

NEMO_  (*Nucleus for European Modelling of the Ocean*) is a state-of-the-art modelling framework for
research activities and forecasting services in ocean and climate sciences,
developed in a sustainable way by the NEMO European consortium since 2008.

This page intends to help you to get started using the NEMO platform and to orientate you to the different levels of information. 
It starts here with NEMO release 4.2.0. 

Reminder: [The former web platform forge](https://forge.ipsl.jussieu.fr/nemo) (SVN+Trac) contains the previous documentation and releases from the beginning of the project up to NEMO 4.0.


Getting started
===============
Getting hands on NEMO: first steps are described in detail in the "How to" NEMO users's guide.
Download, build the environment create the executable, and make a first run are described here: https://sites.nemo-ocean.io/user-guide/. 

If you are already using NEMO with a previous release, refer to the [Migration Guide] (https://sites.nemo-ocean.io/user-guide/migration.html) to help making the move to 4.2.0.

The above users guides cover in detail what is available from gitlab and supported by NEMO System Team.
Aside from this web platform, the tests cases are also available from https://github.com/NEMO-ocean/NEMO-examples. These tests cases can be useful for studentes, outreach, exploring some specific aspects of NEMO with light configurations... It is also set up in order to gather the tests cases you may have developped and want to share with the community. Feel free to contribute! 

A summary on  how to get code dependencies, compile and execute NEMO is also available here
(:file:`./INSTALL.rst`).

Project documentation
=====================

Reference manuals fully describing NEMO  for the three main component

* |OCE| models the ocean {thermo}dynamics and solves the primitive equations (:file:`./src/OCE`)

* |ICE| simulates sea-ice {thermo}dynamics, brine inclusions and  subgrid-scale thickness variations (:file:`./src/ICE`)

* |MBG| models the {on,off}line oceanic tracers transport and biogeochemical processes  (:file:`./src/TOP`)
are available from zenodo

============ ==============================================   =============================================== 
 Component    Reference Manual (from zenondo, DOI to quote)   Reference manual (pdf on line version on gitlab)  
============ ==============================================   ===============================================  
 |NEMO-OCE|   |https://zenodo.org/record/1464816|    
 |NEMO-ICE|   |https://zenodo.org/record/1471689|
 |NEMO-MBG|   |https://zenodo.org/record/1471700|
============ ==============================================   ===============================================  

These reference manuals are the publications that should be cited in your own publications. Please visit [How to cite?](https://www.nemo-ocean.eu/bibliography/how-to-cite/) for details.

New features of 4.2.0 release are described here (:file:`./CHANGES.md`)

Asking questions, echange information
=====================================
- [Register once for all and use the NEMO forums](https://nemo-ocean.discourse.group) to share and discuss with the NEMO community.

- [Register once for all and receive by mail the NEMO newsletter ](https://listes.ipsl.fr/sympa/subscribe/nemo-newsletter) : recommended for all users to receive the major announcements from the project (new releases, open meetings and main informations). Low traffic: about ten messages a year.


Contributing to NEMO visibility: projects and publications
==========================================================
Please help us justifying the NEMO development efforts by

-  Adding your publications using NEMO and its outputs here: https://www.nemo-ocean.eu/bibliography/publications/add

-  Describing your project using NEMO here: https://www.nemo-ocean.eu/projects/add

NEMO also has a `Special Issue`_ in the open-access journal
Geoscientific Model Development (GMD) from the European Geosciences Union (https://gmd.copernicus.org/articles/special_issue40.html).
The main scope is to collect relevant manuscripts covering various topics and
to provide a single portal to assess the model potential and evolution.


More on NEMO's features
=======================
Not only does the NEMO framework model the ocean circulation,
it offers various features to enable

- Create :doc:`embedded zooms<zooms>` seamlessly thanks to 2-way nesting package AGRIF_.
- Opportunity to integrate an :doc:`external biogeochemistry model<tracers>`
- Versatile :doc:`data assimilation<da>`
- Generation of :doc:`diagnostics<diags>` through effective XIOS_ system
- Roll-out Earth system modeling with :doc:`coupling interface<cplg>` based on OASIS_

Several :doc:`built-in configurations<cfgs>` are provided to
evaluate the skills and performances of the model which
can be used as templates for setting up a new configurations (:file:`./cfgs`).

The user can also checkout available :doc:`idealized test cases<tests>` that
address specific physical processes (:file:`./tests`).

A set of :doc:`utilities <tools>` is also provided to {pre,post}process your data (:file:`./tools`).

Contributing to NEMO development
================================

NEMO intends to be written in a way allowing easy plug of developments.
You are also welcome to contribute to the development of the NEMO Shared reference.
NEMO development is driven by  NEMO Consortium planning and producing NEMO's sustainable development in order to
keep a reliable evolving framework.
Development is organised and scheduled through a five years development strategy, Working groups and the activities of the development team (named NEMO System Team) in a yearly workplan. [More information here] (https://forge.nemo-ocean.eu/developers/home/-/wikis/Home)


Disclaimer
==========

The NEMO source code is freely available and distributed under
:download:`CeCILL v2.0 license <../../../LICENSE>` (GNU GPL compatible).

You can use, modify and/or redistribute the software under its terms,
but users are provided only with a limited warranty and the software's authors and
the successive licensor's have only limited liability.
