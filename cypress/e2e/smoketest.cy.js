describe('Smoketest', () => {
    it('Can open the edit page', () => {
        cy.visit('edit/demo/E0000030.xml');

        cy.get('.edepid').should('have.value', 'E0000030');
    });
});
